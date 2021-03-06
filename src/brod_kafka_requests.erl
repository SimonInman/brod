%%%
%%%   Copyright (c) 2014, 2015, Klarna AB
%%%
%%%   Licensed under the Apache License, Version 2.0 (the "License");
%%%   you may not use this file except in compliance with the License.
%%%   You may obtain a copy of the License at
%%%
%%%       http://www.apache.org/licenses/LICENSE-2.0
%%%
%%%   Unless required by applicable law or agreed to in writing, software
%%%   distributed under the License is distributed on an "AS IS" BASIS,
%%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%%   See the License for the specific language governing permissions and
%%%   limitations under the License.
%%%

%%%=============================================================================
%%% @doc
%%% This module manages an opaque of sent-request collection.
%%%
%%% @copyright 2014, 2015 Klarna AB
%%% @end
%%% ============================================================================

%%%_* Module declaration =======================================================
%% @private
-module(brod_kafka_requests).

%%%_* Exports ==================================================================

%% API
-export([ new/0
        , add/2
        , del/2
        , get_caller/2
        , get_corr_id/1
        ]).

-export_type([requests/0]).

-record(requests,
        { corr_id = 0
        , sent    = gb_trees:empty() :: gb_trees:tree()
        }).

-opaque requests() :: #requests{}.

-define(MAX_CORR_ID_WINDOW_SIZE, (?MAX_CORR_ID div 2)).

%%%_* Includes =================================================================
-include("brod_int.hrl").

%%%_* APIs =====================================================================

new() -> #requests{}.

%% @doc Add a new request to sent collection.
%% Return the last corrlation ID and the new opaque.
%% @end
-spec add(requests(), pid()) -> {corr_id(), requests()}.
add(#requests{ corr_id = CorrId
             , sent    = Sent
             } = Requests, Caller) ->
  ok = assert_corr_id(Sent),
  NewSent = gb_trees:insert(CorrId, Caller, Sent),
  NewRequests = Requests#requests{ corr_id = kpro:next_corr_id(CorrId)
                                 , sent    = NewSent
                                 },
  {CorrId, NewRequests}.

%% @doc Delete a request from the opaque collection.
%% Crash if correlation ID is not found.
%% @end
-spec del(requests(), corr_id()) -> requests().
del(#requests{sent = Sent} = Requests, CorrId) ->
  Requests#requests{sent = gb_trees:delete(CorrId, Sent)}.

%% @doc Get caller of a request having the given correlation ID.
%% Crash if the request is not found.
%% @end
-spec get_caller(requests(), corr_id()) -> pid().
get_caller(#requests{sent = Sent}, CorrId) ->
  gb_trees:get(CorrId, Sent).

%% @doc Get the correction to be sent for the next request.
-spec get_corr_id(requests()) -> corr_id().
get_corr_id(#requests{ corr_id = CorrId }) ->
  CorrId.

%%%_* Internal function ========================================================

%% Assert that the in-buffer oldest and newest correlation ids are within a
%% resonable window size. Otherwise it probably means:
%% 1. kafka failed to send response to certain request(s)
%% 2. too many requests sent on to a congested tcp connection.
%% TODO: make it configurable?
assert_corr_id(Sent) ->
  Size = corr_id_window_size(Sent),
  case  Size =< ?MAX_CORR_ID_WINDOW_SIZE of
    true  -> ok;
    false -> erlang:error(corr_id_window_size)
  end.

corr_id_window_size(Sent) ->
  case gb_trees:is_empty(Sent) of
    true -> 0;
    false ->
      {Min, _} = gb_trees:smallest(Sent),
      {Max, _} = gb_trees:largest(Sent),
      erlang:min(Max - Min, Min + ?MAX_CORR_ID - Max) + 1
  end.

%%%_* Emacs ====================================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
