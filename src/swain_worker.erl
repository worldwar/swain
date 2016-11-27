%%%-------------------------------------------------------------------
%%% @author zhuran
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 19. Nov 2016 8:36 AM
%%%-------------------------------------------------------------------
-module(swain_worker).
-author("zhuran").

-behaviour(gen_server).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {socket, phase, remote_socket}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(InnerSocket :: term()) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(InnerSocket) ->
  gen_server:start_link(?MODULE, [InnerSocket], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([InnerSocket]) ->
  io:format("init~n"),
  {ok, #state{socket = InnerSocket, phase = init}, 0}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

handle_info({tcp, Socket, RawData}, State) ->
  {_, S} = do_proxy(Socket, RawData, State),
  {noreply, S};

handle_info(Info, State) ->
  {noreply, State}.

do_proxy(Socket, RawData, #state{phase = init} = State) ->
  case list_to_binary(RawData) of
    <<5, 1, 0>>  ->
      gen_tcp:send(Socket, <<5, 0>>),
      {ok, State#state{phase = head}};
    _ ->
      {bad_message, State#state{phase = abort}}
  end;

do_proxy(Socket, RawData, #state{phase = head} = State) ->
  case list_to_binary(RawData) of
    <<5, Command:8, 0, AddressType:8, Length:8, Address:Length/binary-unit:8, Port:16>> ->
      case gen_tcp:connect(binary_to_list(Address), Port,
        [binary, {packet, 0}]) of
        {ok, RemoteSocket} ->
          gen_tcp:send(Socket, <<5, 0, 0, 1, 0, 0, 0, 0, 0, 0>>),
          {ok, State#state{phase = request, remote_socket = RemoteSocket}};
        _ ->
          {ok, State}
      end;
    _ ->
      {bad_message, State#state{phase = abort}}
  end;

do_proxy(Socket, RawData, #state{phase = request, socket = Socket} = State) ->
  gen_tcp:send(State#state.remote_socket, list_to_binary(RawData)),
  {ok, State#state{phase = request}};

do_proxy(Socket, RawData, #state{phase = request, remote_socket = Socket} = State) ->
  io:format("response raw data: ~p~n", [RawData]),
  gen_tcp:send(State#state.socket, RawData),
  {ok, State#state{phase = request}};

do_proxy(_, _, State) ->
  {bad_message, State#state{phase = abort}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
