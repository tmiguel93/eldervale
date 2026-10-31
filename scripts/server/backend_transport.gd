class_name BackendTransport
extends RefCounted
## Interface do transporte HTTP do BackendClient (injetavel; os testes usam um fake).
## `req`: {method: "GET"|"POST", url: String, headers: PackedStringArray, body: String, timeout_sec: float}.
## `cb` e chamado UMA vez com {status: int, body: String, error: String}: status 0 + error
## ("network" | "timeout" | "cancelled" | "bad_request") quando nao houve resposta HTTP.
## A base e um no-op (nunca chama cb).


func send(_req: Dictionary, _cb: Callable) -> void:
	pass


## Cancela requisicoes em voo SEM chamar os callbacks (ciclo de vida/encerramento).
func cancel_all() -> void:
	pass
