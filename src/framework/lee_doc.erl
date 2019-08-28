%% @doc Utilities for extracting documentation from the model
-module(lee_doc).

-export([make_docs/2, document_values/2]).

-export([ simplesect/2
        , erlang_listing/1
        , xref_key/1
        , refer_value/4
        , docbook/1
        , check_docstrings/1
        , validate_doc_root/4
        ]).

-include("lee_internal.hrl").
-include_lib("typerefl/include/types.hrl").

-type doc() :: term().

-type doc_options() ::
        #{ app_name     := string()
         , introduction => doc()
         , metatypes    := [lee:metatype() | {lee:metatype(), term()}]
         , output_dir   => file:filename()
         }.

-export_type([doc/0, doc_options/0]).

%% @doc Represent text as Erlang code
-spec erlang_listing(iolist()) -> doc().
erlang_listing(Str) ->
    { programlisting, [{language, "erlang"}]
    , [Str]
    }.

%% @doc Make a simple subsection
-spec simplesect(string(), iolist() | [doc()]) -> doc().
simplesect(Title, Doc0) ->
    Doc = case io_lib:deep_char_list(Doc0) of
              true ->
                  [{para, [lists:flatten(Doc0)]}];
              false ->
                  Doc0
          end,
    {para, [{emphasis, [Title]} | Doc]}.

%% @doc Generate a link to the description of a value
-spec xref_key(lee:key()) -> doc().
xref_key(Key) ->
    Node = lee_lib:format("~p", [Key]),
    {xref, [{linkend, Node}], []}.

%% @doc Generate a section that contains short description of a value
%% and a link to the full description
-spec refer_value(lee:model_key(), lee:metatype(), string(), #mnode{}) ->
                         doc().
refer_value(Key, Metatype, Title, MNode) ->
    SectionId = lee_lib:format("~p", [{Metatype, Title}]),
    #mnode{metaparams = Attrs} = MNode,
    Oneliner = ?m_attr(value, oneliner, Attrs, ""),
    {section, [{id, SectionId}]
    , [ {title, [Title]}
      , {para, [Oneliner ++ ", see: ", lee_doc:xref_key(Key)]}
      ]
    }.

%% @doc Parse string as list of XML nodes. Example:
%% ```
%% lee_doc:docbook("<para>Some text</para>
%%                  <para>More text</para>")'''
-spec docbook(string()) -> [doc()].
docbook([]) ->
    [];
docbook(String) ->
    {Doc, Rest} = xmerl_scan:string(String, [{document, false}]),
    [Doc | docbook(Rest)].

%% @private Meta-validation of docstrings
-spec check_docstrings(lee:parameters()) -> lee_lib:check_result().
check_docstrings(Attrs) ->
    CheckOneliner = lee_lib:validate_optional_meta_attr( oneliner
                                                       , printable_unicode_list()
                                                       , Attrs
                                                       , true
                                                       ),
    CheckDoc = case Attrs of
                   #{doc := Doc} ->
                       try docbook(Doc) of
                           _ -> {[], []}
                       catch
                           _:_ -> {["`doc' attribute is not a valid docbook string"], []}
                       end;
                   _ ->
                       {[], ["`doc' attribute is expected"]}
               end,
    lee_lib:compose_checks([CheckOneliner, CheckDoc]).

%% @private Meta-validation of doc root
-spec validate_doc_root(lee:model(), _, lee:key(), #mnode{}) ->
                               lee_lib:check_result().
validate_doc_root(_, _, Key, #mnode{metaparams = Attrs}) ->
    Fun = fun(#{app_name := _}) -> {[], []};
             (_)                -> {["missing `app_name' parameter"], []}
          end,
    lee_lib:perform_checks(Key, Attrs, [fun check_docstrings/1, Fun]).

%% @private
-spec document_value(lee:model_key(), lee:model()) ->
                            doc().
document_value(Key, Model) ->
    #mnode{metaparams = Attrs} = lee_model:get(Key, Model),
    Oneliner = ?m_attr(value, oneliner, Attrs, ""),
    Type = ?m_attr(value, type, Attrs),
    Default =
        case Attrs of
            #{default := DefVal} ->
                DefStr = io_lib:format("~p", [DefVal]),
                [simplesect( "Default value:"
                           , [erlang_listing(DefStr)]
                           )];
            _ ->
                []
        end,
    Description =
        case Attrs of
            #{doc := DocString0} ->
                DocString = ?m_valid(value, docbook(DocString0)),
                [simplesect("Description:", DocString)];
            _ ->
                []
        end,
    Id = lee_lib:format("~p", [Key]),
    { section, [{id, Id}]
    , [ {title, [Id]}
      , {para, [Oneliner]}
      , simplesect("Type:", [erlang_listing(typerefl:print(Type))])
      ] ++ Default ++ Description
    }.

%% @private
-spec document_values(lee:model(), _Config) -> doc().
document_values(Model, _Config) ->
    #model{meta_class_idx = Idx} = Model,
    Keys = maps:get(value, Idx, []),
    [document_value(Key, Model) || Key <- Keys].

%% @private
-spec make_file(atom(), doc(), string()) -> file:filename().
make_file(Top, Data, Id) ->
    RootAttrs = [ {xmlns, "http://docbook.org/ns/docbook"}
                , {version, "5.0"}
                , {id, Id}
                ],
    Doc = {Top, RootAttrs, Data},
    DocStr = xmerl:export_simple([Doc], xmerl_xml, [{prolog, ""}]),
    Filename = filename:join("docs", Id ++ ".xml"),
    ok = filelib:ensure_dir(Filename),
    {ok, FD} = file:open(Filename, [write]),
    try ok = io:format(FD, "~s~n", [DocStr])
    after
        file:close(FD)
    end,
    Filename.

%% @private
-spec metatype_docs( lee:metatype() | {lee:metatype(), term()}
                   , lee:model()
                   ) -> doc().
metatype_docs({MetaType, DocConfig}, Model) ->
    #model{metamodel = Meta} = Model,
    #mnode{metaparams = Attrs} = lee_model:get([metatype, MetaType], Meta),
    Title0 = ?m_attr(documented, doc_chapter_title, Attrs),
    Title = if is_function(Title0, 2) ->
                    Title0(Model, DocConfig);
               is_list(Title0) ->
                    Title0
            end,
    GenDocs = ?m_attr(documented, doc_gen, Attrs),
    Content = GenDocs(Model, DocConfig),
    %% TODO: it's not the way
    ChapterSuffix = case DocConfig of
                        #{chapter_name := CN} ->
                            [$-|CN];
                        _ ->
                            ""
                    end,
    SectionId = lee_lib:format("chapter-~p~s", [MetaType, ChapterSuffix]),
    {chapter, [{id, SectionId}]
    , [{title, [Title]} | Content]
    };
metatype_docs(MetaType, Model) ->
    metatype_docs({MetaType, undefined}, Model).

-spec make_docs(lee:model(), doc_options()) -> ok.
make_docs(Model, Options) ->
    #{metatypes := Metatypes} = Options,
    DocRoot = maps:get(doc_root, Options, ['$doc_root']),
    #mnode{metaparams = Attrs} = lee_model:get(DocRoot, Model),
    AppName = ?m_attr(doc_root, app_name, Attrs),
    Intro = make_intro_chapter(Attrs),
    Chapters = [metatype_docs(MT, Model) || MT <- Metatypes],
    Contents = [{title, [AppName]}, Intro | Chapters],
    Top = make_file(book, Contents, AppName),
    case maps:get(run_pandoc, Options, false) of
        true ->
            {0, _} = run_pandoc(Top, "html"),
            {0, _} = run_pandoc(Top, "man"),
            {0, _} = run_pandoc(Top, "texinfo");
        false ->
            ok
    end.

make_intro_chapter(Attrs) ->
    AppOneliner = ?m_attr(doc_root, oneliner, Attrs),
    AppDoc = docbook(?m_attr(doc_root, doc, Attrs, "")),
    {chapter, [{id, "intro"}]
    , [{title, ["Introduction"]}, {para, [AppOneliner]} | AppDoc]
    }.

run_pandoc(SrcFile, OutFormat) ->
    %% TODO: this is sketchy and wrong
    OutName = filename:rootname(SrcFile) ++ [$.|OutFormat],
    Cmd = lee_lib:format( "pandoc -o '~s' -f docbook -t ~s '~s'"
                        , [OutName, OutFormat, SrcFile]
                        ),
    lee_lib:run_cmd("pandoc", [ "--toc", "-s", "-f", "docbook", "-t", OutFormat, "-o"
                              , OutName, SrcFile
                              ]).
