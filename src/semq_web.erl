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

head_request(Req) ->
    Req:respond({200, headers(), ""}).

delete_request(Req, Queue) -> 
    frontend:deleterequest(Queue),
    Req:respond({200, headers(), ""}).

get_request(Req, Queue) ->
    case frontend:getrequest(Queue) of
        {ok, Message} ->
            Socket = Req:get(socket),
            case gen_tcp:recv(Socket, 0, 0) of 
              {error, 'timeout'} ->
                Req:respond({200, headers(), Message}),
                frontend:removehead(Queue);
               _ ->
                 error_logger:error_report(["client disconnected"])
             end;
                
        {error, Reason} ->
            Req:respond({404, headers(),
                         io_lib:format("~p~n", [Reason])})
    end.

listqueues_request(Req) ->
    {ok, Queues} = frontend:get_all_queue_names(),
    Req:respond({200, headers(), io_lib:format("~p~n", [Queues])}).

post_request(Req, Queue, Message) ->
    frontend:postrequest(Queue, Message),
    Req:respond({200, [{"Content-Type", "text/plain"}], "Posted"}).

process_request("unique_queue_name", Req) ->
    case Req:get(method) of
        'GET' ->
            Req:respond({200, headers(), io_lib:format("~p", [crypto:rand_uniform(16#ffffffffffff, 16#ffffffffffffffff)])});
        'HEAD' ->
            head_request(Req);
         _ ->
            Req:respond({405, [], []})
    end;

process_request("queue/"++Queue, Req) ->
    case Req:get(method) of
        'GET' ->
            get_request(Req, Queue);
        'HEAD' ->
            head_request(Req);
        'POST' ->
            Message = Req:recv_body(),
            post_request(Req, Queue, Message);
        'DELETE' ->
            delete_request(Req, Queue);
        _ ->
            Req:respond({405, [], []})
     end;
    
process_request("queues", Req) ->
    case Req:get(method) of
        'GET' ->
            listqueues_request(Req);
        'HEAD' ->
            head_request(Req);
        _ ->
            Req:respond({405, [], []})
     end.

loop(Req, _DocRoot) ->
    "/" ++ Path = Req:get(path),
    try
        process_request(Path, Req)
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
headers() ->
 [{"Access-Control-Allow-Headers", "Content-Type"}, {"Access-Control-Allow-Origin", "*"}, {"Content-Type", "text/plain"}].


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
    frontend:postrequest(Queue, Message),
    RecievedMessage = frontend:getrequest(Queue),
    ?assertEqual(
       {ok, Message},
       RecievedMessage),
    routing:stop(),
    ok.


pushing_onto_queue_after_get_still_retrieves_message_test() ->
    routing:start_link(),
    Message = "a message to send", 
    Queue = "queueNameNew",
    Pid = spawn(frontend, getrequest, [Queue]),
    timer:sleep(100),
    frontend:postrequest(Queue, "some kind of message"),
    frontend:postrequest(Queue, Message),
    RecievedMessage = frontend:getrequest(Queue),
    ?assertEqual(
       {ok, Message},
       RecievedMessage),
    routing:stop(),
    ok.


-endif.
