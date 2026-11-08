
-module(p07_puertas_sup).
-behaviour(supervisor).

-export([
    start_link/0,
    iniciar_puerta/1,
    detener_puerta/1,
    listar_puertas/0,
    sincronizar_todas/0,
    distribuir_credencial/1
]).

-export([init/1]).

start_link() ->
    supervisor:start_link(
        {local, ?MODULE},
        ?MODULE,
        []
    ).

iniciar_puerta(Id) ->
    ChildSpec = #{
        id => {puerta, Id},
        start => {p07_puerta, start_link, [Id]},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [p07_puerta]
    },
    supervisor:start_child(?MODULE, ChildSpec).

detener_puerta(Id) ->
    ChildId = {puerta, Id},
    case supervisor:terminate_child(?MODULE, ChildId) of
        ok -> supervisor:delete_child(?MODULE, ChildId);
        Error -> Error
    end.

listar_puertas() ->
    supervisor:which_children(?MODULE).

sincronizar_todas() ->
    Credenciales = p07_credenciales:listar(),
    Resultados = [
        p07_puerta:sincronizar_credenciales(Pid, Credenciales)
        || {_Id, Pid, worker, _} <- listar_puertas(),
           is_pid(Pid)
    ],
    {ok, Resultados}.

distribuir_credencial(Credencial) ->
    Resultados = [
        p07_puerta:actualizar_credencial(Pid, Credencial)
        || {_Id, Pid, worker, _} <- listar_puertas(),
           is_pid(Pid)
    ],
    {ok, Resultados}.

init([]) ->
    {ok, {
        #{
            strategy => one_for_one,
            intensity => 10,
            period => 60
        },
        []
    }}.
