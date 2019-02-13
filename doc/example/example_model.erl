-module(example_model).

-include_lib("lee/include/lee.hrl").
-include_lib("lee/include/lee_types.hrl").

-type version() :: string().

-type checkout() :: tag | branch | commit.

-lee_verify({git_repo/0, is_url/0}).
-type git_repo() :: string().

-type dep_spec() :: {atom(), version()} %% Hex-style
                  | {atom(), {git, git_repo()}, {checkout(), string()}} %% Git
                  .

model() ->
  {ok, Model} = lee_model:compile([],
    [ #{ num_jobs =>
           {[value, cli_parameter, environment_variable]
           , #{ oneliner => "Maximal number of parallel jobs"
              , doc => "blah blah"
              , cli_operand => "jobs"
              , cli_short => "j"
              , type => non_neg_integer()
              , default => undefined
              }}
       , num_downloads =>
           {[value, cli_parameter, environment_variable]
           , #{ oneliner => "Maximal number of parallel jobs"
              , doc => "blah blah"
              , cli_operand => "network"
              , cli_short => "n"
              , type => non_neg_integer()
              , default => undefined
              }}
       %% Example node with children:
       , clean =>
           {[command, cli_operation]
           , #{ oneliner => "Clean"
              , doc => "blah blah"
              , cli_operand => "clean"
              }
           , #{ force =>
                  {[value, cli_parameter]
                  , #{ oneliner => "Whatever it means"
                     , doc => "blah blah"
                     , cli_operand => "force"
                     , cli_short => "f"
                     , type => boolean()
                     , default => false
                     }}
              }}
       , deps =>
           {[value, config_file]
           , #{ oneliner => "List of the dependencies"
              , doc => "Blah blah"
              , type => dep_spec()
              }}
      }
    , lee:type_refl([tendon_types], [dep_spec/0])
      %% Just for reference, define a type manually instead of using reflection:
    , lee:namespace([tendom_types]
                   , #{ version =>
                          {[type]
                          , #{ verify =>
                                 fun(_Model, _Self, Str) ->
                                     ok
                                 end
                             }}
                      })
    , tendon_prv_erlc:model()
    , lee:namespace(asn1, tendon_prv_asn1:model())
    , lee:namespace(hex, tendon_prv_hex:model())
    , lee:base_model()
    ]),
  Model.

is_url(Str) ->
  try
    #{} = uri_string:parse(Str),
    ok
  catch
    _:_ ->
      {error, "Expected a URL string"}
  end.
