
-module(p07_control_de_acceso_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        #{
            id => p07_puertas_sup,
            start => {p07_puertas_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [p07_puertas_sup]
        },
        #{
            id => p07_credenciales,
            start => {p07_credenciales, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [p07_credenciales]
        },
        #{
            id => p07_personas_dentro,
            start => {p07_personas_dentro, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [p07_personas_dentro]
        },
        #{
            id => p07_bitacora,
            start => {p07_bitacora, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [p07_bitacora]
        },
        #{
            id => p07_alertas,
            start => {p07_alertas, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [p07_alertas]
        },
        #{
            id => p07_http,
            start => {p07_http, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [p07_http]
        }
    ],

    {ok, {
        #{
            strategy => one_for_one,
            intensity => 10,
            period => 60
        },
        Children
    }}.

