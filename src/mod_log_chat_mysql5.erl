%%%----------------------------------------------------------------------
%%% File    : mod_log_chat_mysql5.erl
%%% Author  : Michael Weibel <michael.weibel@amiadogroup.com>
%%% Original Author  : Jérôme Sautret <jerome.sautret@process-one.net>
%%% Purpose : Log chat messages to a mysql db
%%%----------------------------------------------------------------------

-module(mod_log_chat_mysql5).
-author('michael.weibel@amiadogroup.com').

-behaviour(gen_mod).
-behaviour(gen_server).

%% gen_mod callbacks
-export([start/2, start_link/2,
		stop/1,
		log_packet_send/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
		terminate/2, code_change/3]).

%% -define(ejabberd_debug, true).

-include("ejabberd.hrl").
-include("jlib.hrl").
-include("logger.hrl").


-define(PROCNAME, ?MODULE).

table_name() ->
	"mod_log_chat_mysql5".

%% start db connection
start_link(Host, Opts) ->
	Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
	gen_server:start_link({local, Proc}, ?MODULE, [Host, Opts], []).

%% Start module & start gen_server as a child for the db connection
start(Host, Opts) ->
	ejabberd_hooks:add(user_send_packet, Host, ?MODULE, log_packet_send, 55),
	Proc = gen_mod:get_module_proc(Host, ?PROCNAME),

	ChildSpec =
			{Proc,
				{?MODULE, start_link, [Host, Opts]},
				transient,
				50,
				worker,
				[?MODULE]},
	supervisor:start_child(ejabberd_sup, ChildSpec).

%% stop module (remove hooks) & stop gen server
stop(Host) ->
	ejabberd_hooks:delete(user_send_packet, Host,
		?MODULE, log_packet_send, 55),
	Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
	gen_server:call(Proc, stop),
	supervisor:delete_child(ejabberd_sup, Proc).

%% called from start_link/2 and sets up the db connection
init([_Host, _]) ->
	?INFO_MSG("Starting ~p", [?MODULE]),
	{ok, undefined}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
	?INFO_MSG("Terminate called", []),
	ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call(stop, _From, State) ->
	{stop, normal, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%% odbc_queries:escape or ejabberd_odbc:escape
%%--------------------------------------------------------------------
handle_cast({insert_row, From, FromJid, ToJid, Body, Type}, State) ->
    ejabberd_odbc:sql_query(jlib:nameprep(From#jid.lserver),
	    [<<"INSERT INTO ">>, table_name(), <<" (fromJid, toJid, sentDate, body, type) VALUES ('">>,
		 ejabberd_odbc:escape(FromJid), <<"', '">>, ejabberd_odbc:escape(ToJid), <<"', NOW(), '">>,
	         ejabberd_odbc:escape(Body), <<"', '">>, ejabberd_odbc:escape(Type), <<"');">>]),
	{noreply, State}.

%% handle module infos
handle_info({'DOWN', _MonitorRef, process, _Pid, _Info}, State) ->
	{stop, connection_dropped, State};
handle_info(Info, State) ->
	?INFO_MSG("Got Info:~p, State:~p", [Info, State]),
	{noreply, State}.

%% ejabberd hook
log_packet_send(From, To, Packet) ->
	log_packet(From, To, Packet).

log_packet(From, To, Packet = {xmlel, <<"message">>, Attrs, _Els}) ->
	case xml:get_attr_s("type", Attrs) of
		"error" -> %% we don't log errors
			?DEBUG("dropping error: ~s", [xml:element_to_string(Packet)]),
			ok;
		_ ->
			write_packet(From, To, Packet, xml:get_attr_s("type", Attrs))
	end;
log_packet(_From, _To, _Packet) ->
	ok.

%% parse message and send to db connection gen_server
write_packet(From, To, Packet, Type) ->
	Body = list_to_binary(escape(html, binary_to_list(xml:get_path_s(Packet, [{elem, <<"body">>}, cdata])))),
	case Body of
		"" -> %% don't log empty messages
			?DEBUG("not logging empty message from ~s",[jlib:jid_to_string(From)]),
			ok;
		_ ->
			FromJid = erlang:iolist_to_binary([From#jid.luser, <<"@">>, From#jid.lserver, <<"/">>, From#jid.resource]),
			ResourceLen = length(binary_to_list(To#jid.resource)),
			%% don't include resource when target is muc room
			if
				ResourceLen > 0 ->
					ToJid = erlang:iolist_to_binary([To#jid.luser, <<"@">>, To#jid.lserver, <<"/">>, To#jid.resource]);
				true ->
					ToJid = erlang:iolist_to_binary([To#jid.luser, <<"@">>, To#jid.lserver])
			end,
			Proc = gen_mod:get_module_proc(From#jid.server, ?PROCNAME),
			gen_server:cast(Proc, {insert_row, From, FromJid, ToJid, Body, Type})
	end.

%% ==================
%% SQL Query API
%% ==================

escape(text, Text) ->
	Text;
escape(_, "") ->
	"";
escape(html, [$< | Text]) ->
	"&lt;" ++ escape(html, Text);
escape(html, [$& | Text]) ->
	"&amp;" ++ escape(html, Text);
escape(html, [Char | Text]) ->
	[Char | escape(html, Text)].
