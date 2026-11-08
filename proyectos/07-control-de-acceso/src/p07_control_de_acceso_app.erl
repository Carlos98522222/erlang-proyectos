-module(p07_control_de_acceso_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    case p07_control_de_acceso_sup:start_link() of
        {ok, Pid} ->
            spawn(fun inicializar_puertas/0),
            {ok, Pid};
        Error ->
            Error
    end.

inicializar_puertas() ->
    timer:sleep(1000),
    [p07_puertas_sup:iniciar_puerta(N) || N <- lists:seq(1, 40)],
    p07_puertas_sup:sincronizar_todas(),
    ok.

stop(_State) ->
    ok.
