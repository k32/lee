-module(example_model2).

-export([main/1]).

-include_lib("lee/include/lee_types.hrl").

%% Model definition:
-spec model() -> lee:lee_module().
model() ->
    #{ foo =>
           {[value, cli_param], %% This value is read from CLI
            #{ type => boolean()
             , oneliner => "This value controls fooing"
             , cli_short => $f
             , cli_operand => "foo"
             }}
     , bar =>
           #{ baz =>
                  {[value, os_env], %% This value is read from environment variable
                   #{ type => integer()
                    , oneliner => "This value controls bazing"
                    , default => 42
                    , os_env => "BAZ"
                    }}
            , quux =>
                  {[value, cli_param, os_env],  %% This value is read from both CLI and environment
                   #{ type => nonempty_list(atom())
                    , oneliner => "This value controls quuxing"
                    , default => [foo]
                    , cli_operand => "quux"
                    , os_env => "QUUX"
                    }}
            }
     }.

%% Test data:
-spec data(lee:model(), [string()]) -> lee:data().
data(Model, CliArgs) ->
    %% Create an empty storage:
    Data0 = lee_storage:new(lee_map_storage),
    %% Read environment variables:
    Data1 = lee_os_env:read_to(Model, Data0),
    %% Read CLI arguments and return the resulting data:
    lee_cli:read_to(Model, CliArgs, Data1).

main(CliArgs) ->
    {ok, Model} = lee_model:compile( [lee:base_metamodel()]
                                   , [lee:base_model(), model()]
                                   ),
    %% Get data:
    Data = data(Model, CliArgs),
    case lee:validate(Model, Data) of
        {ok, _Warnings} ->
            %% Print values:
            [begin
                 Val = lee:get(Model, Data, Key),
                 io:format("~p = ~p~n", [Key, Val])
             end || Key <- [[foo], [bar, baz], [bar, quux]]],
            erlang:halt(0);
        {error, Errors, _Warnings} ->
            %% Print error:
            io:format("Invalid configuration: ~s~n", [string:join(Errors, "\n")]),
            erlang:halt(1)
    end.
