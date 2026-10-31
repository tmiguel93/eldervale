import { afterEach, describe, expect, it } from "vitest";
import { setup, type Harness } from "./m4_harness.ts";

let h: Harness;
afterEach(async () => { await h.db.close(); });

const UNKNOWN = "00000000-0000-4000-8000-000000000000";

async function mkPartyWith(h: Harness, n: number) {
  const leader = await h.user();
  const created = await h.call("POST", "/v1/parties", { token: leader.token, body: { character_id: leader.char } });
  const partyId: string = created.json.party.id;
  const members = [];
  for (let i = 0; i < n; i++) {
    const u = await h.user();
    h.advance(1000);
    const inv = await h.call("POST", `/v1/parties/${partyId}/invites`, { token: leader.token, body: { target_character_id: u.char } });
    expect(inv.status).toBe(201);
    const j = await h.call("POST", `/v1/parties/${partyId}/join`, { token: u.token, body: { invite_id: inv.json.invite.id, character_id: u.char } });
    expect(j.status).toBe(200);
    members.push(u);
  }
  return { leader, partyId, members };
}

describe("party: fluxo", () => {
  it("cria, convida, entra, lista, sai e dissolve", async () => {
    h = await setup();
    const a = await h.user();
    const b = await h.user();
    const c = await h.call("POST", "/v1/parties", { token: a.token, body: { character_id: a.char } });
    expect(c.status).toBe(201);
    const pid = c.json.party.id;
    expect(c.json.party.leader_character_id).toBe(a.char);
    expect(c.json.party.members).toHaveLength(1);
    expect(JSON.stringify(c.json)).not.toContain(a.account); // sem account_id na resposta

    const inv = await h.call("POST", `/v1/parties/${pid}/invites`, { token: a.token, body: { target_character_id: b.char } });
    expect(inv.status).toBe(201);
    expect(inv.json.invite.status).toBe("pending");
    const join = await h.call("POST", `/v1/parties/${pid}/join`, { token: b.token, body: { invite_id: inv.json.invite.id, character_id: b.char } });
    expect(join.status).toBe(200);
    expect(join.json.party.members.map((m: any) => m.character_id).sort()).toEqual([a.char, b.char].sort());

    const get = await h.call("GET", `/v1/parties/${pid}`, { token: b.token });
    expect(get.status).toBe(200);
    expect(get.json.party.members.find((m: any) => m.is_leader).character_id).toBe(a.char);

    const lb = await h.call("POST", `/v1/parties/${pid}/leave`, { token: b.token });
    expect(lb.json).toEqual({ party_disbanded: false, new_leader_character_id: null });
    const la = await h.call("POST", `/v1/parties/${pid}/leave`, { token: a.token });
    expect(la.json).toEqual({ party_disbanded: true, new_leader_character_id: null });
    expect((await h.call("GET", `/v1/parties/${pid}`, { token: a.token })).status).toBe(404);
    // personagem livre para nova party
    expect((await h.call("POST", "/v1/parties", { token: a.token, body: { character_id: a.char } })).status).toBe(201);
  });

  it("personagem em no maximo uma party; conta so um personagem por party", async () => {
    h = await setup();
    const a = await h.user();
    await h.call("POST", "/v1/parties", { token: a.token, body: { character_id: a.char } });
    const again = await h.call("POST", "/v1/parties", { token: a.token, body: { character_id: a.char } });
    expect(again.status).toBe(409);
    expect(again.json.error.code).toBe("already_in_party");
    // segundo personagem da mesma conta nao entra na propria party
    const alt = await h.extraChar(a.account);
    const p = (await h.call("GET", "/v1/parties/" + UNKNOWN, { token: a.token }));
    expect(p.status).toBe(404);
    const mine = await h.db.query<{ id: string }>("SELECT party_id AS id FROM party_members WHERE character_id=$1", [a.char]);
    const inv = await h.call("POST", `/v1/parties/${mine.rows[0]!.id}/invites`, { token: a.token, body: { target_character_id: alt } });
    expect(inv.status).toBe(201);
    const j = await h.call("POST", `/v1/parties/${mine.rows[0]!.id}/join`, { token: a.token, body: { invite_id: inv.json.invite.id, character_id: alt } });
    expect(j.status).toBe(409);
    expect(j.json.error.code).toBe("account_already_in_party");
  });
});

describe("party: limite de 4", () => {
  it("5o membro e recusado (sequencial)", async () => {
    h = await setup();
    const { leader, partyId } = await mkPartyWith(h, 3);
    const extra = await h.user();
    const inv = await h.call("POST", `/v1/parties/${partyId}/invites`, { token: leader.token, body: { target_character_id: extra.char } });
    expect(inv.status).toBe(409);
    expect(inv.json.error.code).toBe("party_full");
  });

  it("concorrencia: 6 convidados entram ao mesmo tempo, nunca passa de 4", async () => {
    h = await setup();
    const { leader, partyId } = await mkPartyWith(h, 1); // lider + 1 = 2
    const guests = [];
    for (let i = 0; i < 6; i++) {
      const u = await h.user();
      const inv = await h.call("POST", `/v1/parties/${partyId}/invites`, { token: leader.token, body: { target_character_id: u.char } });
      expect(inv.status).toBe(201);
      guests.push({ u, inviteId: inv.json.invite.id });
    }
    const results = await Promise.all(
      guests.map((g) => h.call("POST", `/v1/parties/${partyId}/join`, { token: g.u.token, body: { invite_id: g.inviteId, character_id: g.u.char } })),
    );
    const okCount = results.filter((r) => r.status === 200).length;
    const full = results.filter((r) => r.status === 409 && r.json.error.code === "party_full").length;
    expect(okCount).toBe(2);
    expect(full).toBe(4);
    const n = await h.db.query<{ n: number }>("SELECT count(*)::int AS n FROM party_members WHERE party_id=$1", [partyId]);
    expect(n.rows[0]!.n).toBe(4);
  });

  it("concorrencia: o mesmo convite usado duas vezes entra uma so vez", async () => {
    h = await setup();
    const { leader, partyId } = await mkPartyWith(h, 0);
    const u = await h.user();
    const inv = await h.call("POST", `/v1/parties/${partyId}/invites`, { token: leader.token, body: { target_character_id: u.char } });
    const body = { invite_id: inv.json.invite.id, character_id: u.char };
    const rs = await Promise.all([1, 2, 3].map(() => h.call("POST", `/v1/parties/${partyId}/join`, { token: u.token, body })));
    expect(rs.filter((r) => r.status === 200)).toHaveLength(1);
    expect(rs.filter((r) => r.status === 409)).toHaveLength(2);
  });
});

describe("party: convites", () => {
  it("expirado, usado, duplicado, de outra party, de outro alvo", async () => {
    h = await setup({ parties: { inviteTtlSeconds: 60 } });
    const { leader, partyId } = await mkPartyWith(h, 0);
    const other = await mkPartyWith(h, 0);
    const u = await h.user();
    const v = await h.user();

    const inv = await h.call("POST", `/v1/parties/${partyId}/invites`, { token: leader.token, body: { target_character_id: u.char } });
    expect(inv.json.invite.expires_at).toBe(new Date(h.clock.t + 60_000).toISOString());
    // duplicado pendente
    const dup = await h.call("POST", `/v1/parties/${partyId}/invites`, { token: leader.token, body: { target_character_id: u.char } });
    expect(dup.status).toBe(409);
    expect(dup.json.error.code).toBe("invite_pending");
    // convite da party A usado na party B => 404
    const wrongParty = await h.call("POST", `/v1/parties/${other.partyId}/join`, { token: u.token, body: { invite_id: inv.json.invite.id, character_id: u.char } });
    expect(wrongParty.status).toBe(404);
    // convite de u usado por v => 404 (v nao e dono do char u)
    const stolen = await h.call("POST", `/v1/parties/${partyId}/join`, { token: v.token, body: { invite_id: inv.json.invite.id, character_id: u.char } });
    expect(stolen.status).toBe(404);
    // v com o proprio personagem e o convite de u => 404
    const wrongTarget = await h.call("POST", `/v1/parties/${partyId}/join`, { token: v.token, body: { invite_id: inv.json.invite.id, character_id: v.char } });
    expect(wrongTarget.status).toBe(404);

    // expira
    h.advance(61_000);
    const exp = await h.call("POST", `/v1/parties/${partyId}/join`, { token: u.token, body: { invite_id: inv.json.invite.id, character_id: u.char } });
    expect(exp.status).toBe(409);
    expect(exp.json.error.code).toBe("invite_expired");
    // convite expirado permite novo convite (o antigo vira 'expired')
    const inv2 = await h.call("POST", `/v1/parties/${partyId}/invites`, { token: leader.token, body: { target_character_id: u.char } });
    expect(inv2.status).toBe(201);
    const st = await h.db.query<{ status: string }>("SELECT status FROM party_invites WHERE id=$1", [inv.json.invite.id]);
    expect(st.rows[0]!.status).toBe("expired");
    const okJoin = await h.call("POST", `/v1/parties/${partyId}/join`, { token: u.token, body: { invite_id: inv2.json.invite.id, character_id: u.char } });
    expect(okJoin.status).toBe(200);
    // reuso do convite aceito
    await h.call("POST", `/v1/parties/${partyId}/leave`, { token: u.token });
    const reuse = await h.call("POST", `/v1/parties/${partyId}/join`, { token: u.token, body: { invite_id: inv2.json.invite.id, character_id: u.char } });
    expect(reuse.status).toBe(409);
    expect(reuse.json.error.code).toBe("invite_not_pending");
  });

  it("so o lider convida/expulsa; alvo ja em party e recusado", async () => {
    h = await setup();
    const { leader, partyId, members } = await mkPartyWith(h, 1);
    const m = members[0]!;
    const u = await h.user();
    const byMember = await h.call("POST", `/v1/parties/${partyId}/invites`, { token: m.token, body: { target_character_id: u.char } });
    expect(byMember.status).toBe(403);
    const kickByMember = await h.call("POST", `/v1/parties/${partyId}/kick`, { token: m.token, body: { character_id: leader.char } });
    expect(kickByMember.status).toBe(403);
    const inParty = await h.call("POST", `/v1/parties/${partyId}/invites`, { token: leader.token, body: { target_character_id: m.char } });
    expect(inParty.status).toBe(409);
    expect(inParty.json.error.code).toBe("target_in_party");
    const self = await h.call("POST", `/v1/parties/${partyId}/kick`, { token: leader.token, body: { character_id: leader.char } });
    expect(self.status).toBe(400);
    const kick = await h.call("POST", `/v1/parties/${partyId}/kick`, { token: leader.token, body: { character_id: m.char } });
    expect(kick.status).toBe(200);
    expect((await h.call("GET", `/v1/parties/${partyId}`, { token: m.token })).status).toBe(404);
    expect((await h.call("POST", `/v1/parties/${partyId}/kick`, { token: leader.token, body: { character_id: m.char } })).status).toBe(404);
  });
});

describe("party: saida do lider", () => {
  it("transfere ao membro mais antigo; ultimo a sair encerra e revoga convites", async () => {
    h = await setup();
    const { leader, partyId, members } = await mkPartyWith(h, 2);
    const [m1, m2] = members as [typeof leader, typeof leader];
    const pending = await h.user();
    await h.call("POST", `/v1/parties/${partyId}/invites`, { token: leader.token, body: { target_character_id: pending.char } });
    const l = await h.call("POST", `/v1/parties/${partyId}/leave`, { token: leader.token });
    expect(l.json).toEqual({ party_disbanded: false, new_leader_character_id: m1.char });
    const view = await h.call("GET", `/v1/parties/${partyId}`, { token: m2.token });
    expect(view.json.party.leader_character_id).toBe(m1.char);
    // novo lider pode convidar; ex-lider nao ve mais a party
    expect((await h.call("GET", `/v1/parties/${partyId}`, { token: leader.token })).status).toBe(404);
    const u = await h.user();
    expect((await h.call("POST", `/v1/parties/${partyId}/invites`, { token: m1.token, body: { target_character_id: u.char } })).status).toBe(201);
    await h.call("POST", `/v1/parties/${partyId}/leave`, { token: m2.token });
    const last = await h.call("POST", `/v1/parties/${partyId}/leave`, { token: m1.token });
    expect(last.json.party_disbanded).toBe(true);
    const inv = await h.db.query<{ status: string }>("SELECT status FROM party_invites WHERE party_id=$1", [partyId]);
    expect(inv.rows.some((r) => r.status === "pending")).toBe(false);
    expect(inv.rows.filter((r) => r.status === "revoked")).toHaveLength(2);
    const p = await h.db.query<{ disbanded_at: unknown }>("SELECT disbanded_at FROM parties WHERE id=$1", [partyId]);
    expect(p.rows[0]!.disbanded_at).not.toBeNull();
  });
});

describe("party: ownership e isolamento", () => {
  it("personagem alheio e party alheia => 404; sem token => 401; ids invalidos => 400", async () => {
    h = await setup();
    const a = await h.user();
    const b = await h.user();
    expect((await h.call("POST", "/v1/parties", { token: b.token, body: { character_id: a.char } })).status).toBe(404);
    const c = await h.call("POST", "/v1/parties", { token: a.token, body: { character_id: a.char } });
    const pid = c.json.party.id;
    expect((await h.call("GET", `/v1/parties/${pid}`, { token: b.token })).status).toBe(404);
    expect((await h.call("POST", `/v1/parties/${pid}/invites`, { token: b.token, body: { target_character_id: b.char } })).status).toBe(404);
    expect((await h.call("POST", `/v1/parties/${pid}/leave`, { token: b.token })).status).toBe(404);
    expect((await h.call("POST", `/v1/parties/${pid}/kick`, { token: b.token, body: { character_id: a.char } })).status).toBe(404);
    expect((await h.call("GET", `/v1/parties/${pid}`)).status).toBe(401);
    expect((await h.call("GET", "/v1/parties/nao-e-uuid", { token: a.token })).status).toBe(400);
    expect((await h.call("POST", "/v1/parties", { token: a.token, body: { character_id: 5 } })).status).toBe(400);
    expect((await h.call("POST", "/v1/parties", { token: a.token, body: [1] })).status).toBe(400);
    // personagem apagado (soft delete) nao cria party
    await h.db.query("UPDATE characters SET deleted_at = now() WHERE id=$1", [b.char]);
    expect((await h.call("POST", "/v1/parties", { token: b.token, body: { character_id: b.char } })).status).toBe(404);
  });
});
