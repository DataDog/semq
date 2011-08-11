%% @author Mochi Media <dev@mochimedia.com>
%% @copyright 2010 Mochi Media <dev@mochimedia.com>

%% @doc Web server for semq.

-module(semq_web).
-author("Mochi Media <dev@mochimedia.com>").

-export([start/1, stop/0, loop/2]).
-import(frontend).
-import(routing).

%% External API

start(Options) ->
    routing:start_link(),
    {DocRoot, Options1} = get_option(docroot, Options),
    Loop = fun (Req) ->
                   ?MODULE:loop(Req, DocRoot)
           end,
    mochiweb_http:start([{name, ?MODULE}, {loop, Loop} | Options1]).

stop() ->
    mochiweb_http:stop(?MODULE).

get_request(Req, Queue) ->
    case frontend:getrequest(Queue) of
        {ok, Message} ->
            Req:respond({200, [{"Content-Type", "text/plain"}],
                         Message});
        {error, Reason} ->
            Req:respond({404, [{"Content-Type", "text/plain"}],
                         [io:format("~p~n", [Reason])]})
    end.
post_request(Req, Queue, Message) ->
    frontend:postrequest(Queue, Message),
    Req:respond({200, [{"Content-Type", "text/plain"}], "Posted"}).

loop(Req, DocRoot) ->
    "/" ++ Path = Req:get(path),
    try
        case Req:get(method) of
            Method when Method =:= 'GET'; Method =:= 'HEAD' ->
                case Path of
                    "post/" ++ MessageAndQueue ->
                        [Queue | Message] = string:tokens(MessageAndQueue, "/"),
                        post_request(Req, Queue, string:join(Message, "/"));
                    Queue ->
                        get_request(Req, Queue)
                end;
            'POST' ->
                case Path of
                    Queue ->
                        Message = Req:recv_body(),
                        post_request(Req, Queue, Message)
                end;
            _ ->
                Req:respond({501, [], []})
        end
    catch
        Type:What ->
            Report = ["web request failed",
                      {path, Path},
                      {type, Type}, {what, What},
                      {trace, erlang:get_stacktrace()}],
            error_logger:error_report(Report),
            %% NOTE: mustache templates need \ because they are not awesome.
            Req:respond({500, [{"Content-Type", "text/plain"}],
                         "request failed, sorry\n"})
    end.

%% Internal API

get_option(Option, Options) ->
    {proplists:get_value(Option, Options), proplists:delete(Option, Options)}.

%%
%% Tests
%%
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

messages_put_onto_queue_can_be_retrieved_test() ->
    routing:start_link(),
    Message = "a message to send", 
    frontend:postrequest("queueName", Message),
    RecievedMessage = frontend:getrequest("queueName"),
    ?assertEqual(
       {ok, Message},
       RecievedMessage),
    routing:stop(),
    ok.

messages_put_onto_queue_can_be_retrieved_in_correct_order_test() ->
    routing:start_link(),
    Queue = "queueName",
    Messages = ["one", "two", "three", "four"], 
    lists:foreach(fun(M) -> frontend:postrequest(Queue, M) end, Messages),
    RecievedMessages = lists:map(fun (_) -> frontend:getrequest(Queue) end, Messages),
    ExpectedMessages = lists:map(fun (M) -> {ok, M} end, Messages),
    ?assertEqual(
       ExpectedMessages,
       RecievedMessages),
    routing:stop(),
    ok.

if_request_dies_message_remains_in_queue_test() ->
    routing:start_link(),
    Message = "a message to send", 
    Queue = "queueName",
    Pid = spawn(frontend, getrequest, [Queue]),
    exit(Pid, "reason"),
    frontend:postrequest("queueName", Message),
    RecievedMessage = frontend:getrequest("queueName"),
    ?assertEqual(
       {ok, Message},
       RecievedMessage),
    routing:stop(),
    ok.


-endif.
