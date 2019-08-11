-module(lee_doc).

-export([make_docs/2, document_values/2]).

-export([ simplesect/2
        , erlang_listing/1
        , xref_key/1
        , refer_value/4
        , docbook/1
        ]).

-include("lee_internal.hrl").

-type doc() :: term().

-type doc_options() ::
        #{ app_name     := string()
         , introduction => doc()
         , metatypes    := [lee:metatype() | {lee:metatype(), term()}]
         , output_dir   => file:filename()
         }.

-export_type([doc/0, doc_options/0]).

-spec erlang_listing(iolist()) -> doc().
erlang_listing(Str) ->
    { programlisting, [{language, "erlang"}]
    , [Str]
    }.

-spec simplesect(string(), iolist() | [doc()]) -> doc().
simplesect(Title, Doc0) ->
    Doc = case io_lib:deep_char_list(Doc0) of
              true ->
                  [{para, [lists:flatten(Doc0)]}];
              false ->
                  Doc0
          end,
    {para, [{emphasis, [Title]} | Doc]}.

-spec xref_key(lee:key()) -> doc().
xref_key(Key) ->
    Node = lee_lib:format("~p", [Key]),
    {xref, [{linkend, Node}], []}.

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

-spec docbook(string()) -> [doc()].
docbook([]) ->
    [];
docbook(String) ->
    {Doc, Rest} = xmerl_scan:string(String, [{document, false}]),
    [Doc | docbook(Rest)].

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

-spec document_values(lee:model(), _Config) -> doc().
document_values(Model, _Config) ->
    #model{meta_class_idx = Idx} = Model,
    Keys = maps:get(value, Idx, []),
    [document_value(Key, Model) || Key <- Keys].

-spec make_file(atom(), doc(), string()) -> file:filename().
make_file(Top, Data, Id) ->
    RootAttrs = [ {xmlns, "http://docbook.org/ns/docbook"}
                , {version, "5.0"}
                , {id, Id}
                ],
    Doc = {Top, RootAttrs, Data},
    DocStr = xmerl:export_simple([Doc], xmerl_xml, [{prolog, ""}]),
    Filename = filename:join("lee_doc", Id ++ ".xml"),
    ok = filelib:ensure_dir(Filename),
    {ok, FD} = file:open(Filename, [write]),
    try ok = io:format(FD, "~s~n", [DocStr])
    after
        file:close(FD)
    end,
    Filename.

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
