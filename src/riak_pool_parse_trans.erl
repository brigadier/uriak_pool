-module(riak_pool_parse_trans).
-export([parse_transform/2]).

-compile(export_all).

parse_transform(Forms, _Options) ->
    Name = parse_trans:get_module(Forms),
    {FunF, SpecF} =
        case Name of
            riak_pool -> {fun pool_fn/2, fun fix_pool_sp/2};
            riak_pool_auto -> {fun pool_auto_fn/2, fun fix_pool_auto_sp/2};
            _ -> parse_trans:error(wrong_module, [], [{module, Name}])
        end,
    Tree = get_syntax_tree(riakc_pb_socket),
    Analyzed = erl_syntax_lib:analyze_forms(Tree),
    AllFuns = ordsets:from_list(proplists:get_value(functions, Analyzed)),
    Exports = ordsets:from_list(proplists:get_value(exports, Analyzed)),
    InterestingFuns =
        ordsets:filter(
          fun is_good_fun/1, ordsets:intersection(AllFuns, Exports)),

    FunsForms = [FunF(F, A) || {F, A} <- ordsets:to_list(InterestingFuns)],
    ExportForms =
        [{attribute, 0, export,
          [{F, A} || {function, 0, F, A, _} <- FunsForms]}],

    InnerTypes =
        [Type || {type, {Type, _, _}} <-
                     proplists:get_value(attributes, Analyzed),
                 is_atom(Type)],
    OrigSpecs = get_specs(Tree, InterestingFuns),
    SpecForms = [SpecF(Sp, InnerTypes) || Sp <- OrigSpecs],

    Forms0 = parse_trans:do_insert_forms(
               below, SpecForms, Forms, undefined),
    Forms1 = parse_trans:do_insert_forms(
               below, FunsForms, Forms0, undefined),
    Forms2 = parse_trans:do_insert_forms(
               above, ExportForms, Forms1,
               parse_trans:initial_context(Forms1, [])),
    parse_trans:return(Forms2,
                       parse_trans:initial_context(Forms2, [])).

get_syntax_tree(M)->
    {ok,{_,[{abstract_code,{_,AC}}]}} =
        beam_lib:chunks(code:which(M), [abstract_code]),
    {tree, form_list, _, Tree} = erl_syntax:form_list(AC),
    Tree.

get_specs([], _)->[];
get_specs([{attribute, _, spec, {{F,A}, _}} = Sp | R], IFs)->
    case ordsets:is_element({F,A}, IFs) of
        true -> [Sp | get_specs(R, IFs)];
        false -> get_specs(R, IFs)
    end;
get_specs([_|R], IFs) ->
    get_specs(R, IFs).

is_good_fun({F, _A})->
    not lists:member(F,
          [set_options, get_client_id, set_client_id,
           default_timeout, start_link, start, stop, terminate]).
%%------------------------------------------------------------

tmap({type, _, Type, TParams}, IT)->
    maybe_remote_type({type, 0, Type, tmap(TParams, IT)}, IT);
tmap(T, IT) when is_tuple(T) ->
    list_to_tuple(tmap(tuple_to_list(T), IT));
tmap(L, IT) when is_list(L) ->
    [tmap(E, IT) || E<- L];
tmap(Other, _IT) -> Other.

maybe_remote_type({type, _, Type, TypeParams},
                  InternalTypes)->
    case lists:member(Type, InternalTypes) of
        true ->
            {remote_type,0,
             [{atom,0,riakc_pb_socket},
              {atom,0,Type},
              TypeParams]};
        false ->
            {type, 0, Type, TypeParams}
    end.

fix_pool_sp(Sp, IT)->
    fix_sp(Sp, IT, 0,
           fun([{type, _, pid, []} | OtherArgs])->
                   [{type,0,worker,[]} | tmap(OtherArgs, IT)]
           end).
%% -spec delete_vclock(worker(),
%%                     riakc_pb_socket:bucket() | string(),
%%                     riakc_pb_socket:key() | string(),
%%                     vclock:vclock(),
%%                     riakc_pb_socket:riak_pbc_options(),
%%                     timeout()) ->
%%                        ok | {error, term()}.

fix_pool_auto_sp(Sp, IT)->
    fix_sp(Sp, IT, 1,
           fun([{type, _, pid, []} | OtherArgs])->
                   tmap(OtherArgs, IT)
           end).

fix_sp({attribute,_,spec,
             {{Fun, Arity},
              [{type,_,'fun',
                [{type,_,product, ArgTypes},
                 ResType]}]}}, InternalTypes, DArity, ArgUpd)->
    {attribute,0,spec,
     {{Fun, Arity-DArity},
      [{type,0,'fun',
        [{type,0,product, ArgUpd(ArgTypes)},
         tmap(ResType, InternalTypes)]}]}}.
%%------------------------------------------------------------

pool_fn(F,A)->
    Vars = varlist(A-1),
    {function, 0, F, A,
     [{clause, 0,
       [{tuple,0,
         [{var, 0, '_Pool'},
          {var,0, 'Worker'}]}
        | Vars],
       [],
       [{call, 0,
         {remote,0,{atom,0,riakc_pb_socket},{atom,0,F}},
         [{var, 0, 'Worker'} | Vars]}]}]}.
%% asdf({_Pool,Worker}, A, B) ->
%%     riakc_pb_socket:asdf(Worker, A, B).

pool_auto_fn(F,A)->
    Vars = varlist(A-1),
    {function, 0, F, A-1,
     [{clause, 0,
       Vars,
       [],
       [{call, 0,
         {remote,0,{atom,0,riak_pool},{atom,0, with_worker}},
         [{atom, 0, riak_pool},
          {atom, 0, F},
          to_list(Vars)]}]}]}.
%% asdf(A, B, C) ->
%%     riak_pool:with_worker(riak_pool, asdf, [A,B,C]).

to_list([])-> {nil,0};
to_list([H|T])->
    {cons,0, H, to_list(T)}.

varlist(N)->
    [{var, 0, list_to_atom([I])}
     || I <- lists:seq($A, $A+N-1)].
%%------------------------------------------------------------

%% pp(F)->
%%     io:format("~s~n", [erl_pp:form(F)]).

%% test()->
%%     pp(pool_fn(pool, 5)),
%%     pp(pool_auto_fn(pool_auto, 5)).

%% sp()->
%%     {attribute,339,spec,
%%      {{delete_vclock,6},
%%       [{type,339,'fun',
%%         [{type,339,product,
%%           [{type,339,pid,[]},
%%            {type,339,union,
%%             [{type,339,bucket,[]},{type,339,string,[]}]},
%%            {type,339,union,
%%             [{type,339,key,[]},{type,339,string,[]}]},
%%            {remote_type,339,
%%             [{atom,339,vclock},{atom,339,vclock},[]]},
%%            {type,340,riak_pbc_options,[]},
%%            {type,340,timeout,[]}]},
%%          {type,340,union,
%%           [{atom,340,ok},
%%            {type,340,tuple,
%%             [{atom,340,error},{type,340,term,[]}]}]}]}]}}.
%% -spec delete_vclock(pid(),
%%                     bucket() | string(),
%%                     key() | string(),
%%                     vclock:vclock(),
%%                     riak_pbc_options(),
%%                     timeout()) ->
%%                        ok | {error, term()}.