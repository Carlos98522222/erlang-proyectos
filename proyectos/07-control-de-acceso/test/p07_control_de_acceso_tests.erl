-module(p07_control_de_acceso_tests).

-include_lib("eunit/include/eunit.hrl").

arbol_de_supervision_test_() ->
    {setup,
        fun iniciar_supervisor/0,
        fun detener_supervisor/1,
        fun(Pid) ->
            [
                ?_assert(is_process_alive(Pid)),
                ?_assertEqual(
                    Pid,
                    whereis(p07_control_de_acceso_sup)
                ),
                ?_assert(is_list(supervisor:which_children(
                    p07_control_de_acceso_sup
                )))
            ]
        end
    }.

iniciar_supervisor() ->
    case p07_control_de_acceso_sup:start_link() of
        {ok, Pid} ->
            unlink(Pid),
            Pid;
        {error, {already_started, Pid}} ->
            Pid
    end.

detener_supervisor(Pid) ->
    case is_process_alive(Pid) of
        true -> exit(Pid, shutdown);
        false -> ok
    end.
