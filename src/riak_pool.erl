%%% Copyright 2012-2013 Unison Technologies, Inc.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.

-module(riak_pool).
-compile({parse_transform, riak_pool_parse_trans}).

-export([
         with_worker/1, with_worker/2, with_worker/3,
         get_worker/0, get_worker/1, free_worker/1,
         call_worker/3
        ]).

%% @TODO try test this optimization.
%% with_worker(Fun) when is_function(Fun, 1) ->
%%     {IsFromDict, Worker} =
%%         case get($riak_pool_worker) of
%%             undefined ->
%%                 Worker = riak_pool:get_worker(),
%%                 put($riak_pool_worker, Worker),
%%                 {false, Worker};
%%             Worker ->
%%                 {true, Worker}
%%         end,
%%     try
%%         Fun(Worker)
%%     after
%%         case IsFromDict of
%%             true  -> pass;
%%             false ->
%%                 erase($riak_pool_worker),
%%                 catch(riak_pool:free_worker(Worker))
%%         end
%%     end.

with_worker(Fun)        -> do_with_worker(Fun).
with_worker(Fun, Args)  -> do_with_worker({Fun, Args}).
with_worker(M, F, Args) -> do_with_worker({M, F, Args}).

do_with_worker(Fun) ->
    case get_worker() of
        {error, _W} = Error -> Error;
        Worker ->
            try
                apply_worker_operation(Worker, Fun)
            after
                riak_pool:free_worker(Worker)
            end
    end.

apply_worker_operation(Worker, Fun) when is_function(Fun, 1) ->
    Fun(Worker);
apply_worker_operation(Worker, {M, F, A}) ->
    apply(M, F, [Worker | A]);
apply_worker_operation(Worker, {F, A}) ->
    apply(F, [Worker | A]).


-type worker() :: {atom(), pid()}.

-spec call_worker(atom() | worker(), fun(), [term()]) -> term().
call_worker({_Pool, WorkerPid}, Function, Args)->
    apply(riakc_pb_socket , Function, [WorkerPid|Args]);
call_worker(Pool, Function, Args) when is_atom(Pool) ->
    case get_worker(Pool) of
        {error, _W} = Error -> Error;
        Worker ->
            try
                call_worker(Worker, Function, Args)
            after
                riak_pool:free_worker(Worker)
            end
    end.

-spec get_worker() -> worker().
get_worker()->
    do_get_worker(riak_pool_balancer:get_pool()).

-spec get_worker(AppName :: atom()) -> worker().
get_worker(AppName)->
    do_get_worker(riak_pool_balancer:get_pool(AppName)).

do_get_worker({error, _W} = Error) -> Error;
do_get_worker(Pool) ->
    case poolboy:checkout(Pool) of
        Pid when is_pid(Pid) ->
            {Pool, Pid};
        Error ->
            {error, {pool_checkout, Error}}
    end.

-spec free_worker(worker())-> ok.
free_worker({Pool, Worker})->
    poolboy:checkin(Pool, Worker).
