
-module(p07_accesos).

-export([
    intentar/2
]).

intentar(IdPuerta, IdCredencial) ->
    case p07_puertas_sup:listar_puertas() of
        Puertas ->
            case lists:keyfind(
                {puerta, IdPuerta},
                1,
                Puertas
            ) of
                {{puerta, IdPuerta}, Pid, worker, _} when is_pid(Pid) ->
                    p07_acceso:intentar(Pid, IdCredencial);

                false ->
                    {error, puerta_no_encontrada}
            end
    end.
