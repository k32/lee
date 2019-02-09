-ifndef(LEE_HRL).
-define(LEE_HRL, true).

-define(children, '$children').

-record(type,
        { id               :: lee:key()
        , refinement = #{} :: map()
        , parameters = []  :: [lee:type()]
        }).

-endif.
