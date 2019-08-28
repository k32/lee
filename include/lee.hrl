-ifndef(LEE_HRL).
-define(LEE_HRL, true).

-define(children, '$children').

-define(key_elements, key_elements).

-define(lcl(A), {'$child', A}). %% Lee ChiLd

-define(lsngl, ?lcl([])).

-define(is_storage(A), (element(1, (A)) =:= lee_tree)).

%% Internal mnode definition
-record(mnode,
        { metatypes = []    :: ordsets:set(atom())
        , metaparams = #{}  :: map()
        }).

-record(type,
        { id                :: lee:key()
        , refinement = #{}  :: map()
        , parameters = []   :: [lee:type()]
        }).

%% (Documentation purpose) Specifies that `Code' can't crash if the
%% model has been properly validated according to the rules of
%% `MetaType'. Use this macro to keep track of things that should be
%% validated.
-define(m_valid(MetaType, Code), Code).

%% Get a mandatory attribute from the attribute map `Attrs', assuming
%% the latter is valid under `MetaType'
-define(m_attr(MetaType, Attr, Attrs), ?m_valid(MetaType, maps:get(Attr, Attrs))).

%% Get an optional attribute from the attribute map `Attrs', assuming
%% the latter is valid under `MetaType'
-define(m_attr(MetaType, Attr, Attrs, Default),
        ?m_valid(MetaType, maps:get(Attr, Attrs, Default))).

-endif.
