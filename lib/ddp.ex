require Logger

defmodule Philae.DDP do
  use HTTPoison.Base
  alias Philae.WebSocketClient
  alias Poison, as: JSON
  use GenServer

  def start_link(url, handler_module, subscriber) do
    GenServer.start_link(__MODULE__, [url, handler_module, subscriber])
  end

  def init([url, handler_module, subscriber]) do
    {:ok, client_pid} = WebSocketClient.start_link(url, __MODULE__, self)
    send_connect_message(client_pid)
    {:ok, %{client: client_pid, subscriber: subscriber, handler_module: handler_module, subscriber: subscriber}}
  end

  # Client API

  def connect(url, handler_module, subscriber) do
    start_link(url, handler_module, subscriber)
  end

  def subscribe(pid, collection) do
    GenServer.call(pid, {:subscribe, collection})
  end

  def unsubscribe(pid, collection_id) do
    GenServer.call(pid, {:unsubscribe, collection_id})
  end

  def handle(pid, msg) do
    GenServer.call(pid, {:handle_message, msg})
  end

  def method(pid, method, args) do
    GenServer.call(pid, {:method, method, args})
  end

  # Server API

  def handle_call({:method, method_name, args}, _from, %{:client => client_pid} = state) do
    send client_pid, {:send, json!(%{msg: "method", method: method_name, params: args, id: id = UUID.uuid4})}
    {:reply, {:ok, id}, state}
  end

  def handle_call({:subscribe, collection}, _from, %{:client => client_pid} = state) do
    {^collection, id} = sub(client_pid, collection)
    {:reply, {collection, id}, state}
  end

   def handle_call({:unsubscribe, collection_id}, _from, %{:client => client_pid} = state) do
    send client_pid, {:send, json!(%{msg: "unsub", id: collection_id})}
    {:reply, {collection_id}, state}
  end

  def handle_call({:handle_message, msg}, _from, %{:client => client_pid, :subscriber => subscriber, :handler_module => handler_module} = state) do
    {:ok, message} = JSON.decode(msg)
    handle_message(client_pid, message, {subscriber, handler_module})
    {:reply, :ok, state}
  end

  def handle_message(client_pid, %{"msg" => "ping"}, _state) do
    send_json_message(client_pid, %{msg: "pong"})
  end

  def handle_message(client_pid, %{"msg" => "ping", "id" => id}, _state) do
    send_json_message(client_pid, %{msg: "pong", id: id})
  end

  def handle_message(_client_pid, %{"msg" => callback} = message, {subscriber, handler_module}) do
    #Logger.info "DDDOOOOO"
    #Logger.info "handler_module " <> inspect(handler_module)
    #Logger.info "callback " <> inspect(callback)
    #Logger.info "subscriber " <> inspect(subscriber)
    #Logger.info "message " <> inspect(message)
    apply(handler_module, String.to_existing_atom(callback), [subscriber, message])
  end

  def handle_message(_client_pid, message, _state) do
    Logger.info "Unhandled message received " <> inspect(message)
  end

  def send_connect_message(client_pid) do
    send client_pid, {:send, json!(%{msg: "connect", version: "1", support: ["1","pre2","pre1"]})}
  end

  def sub(client_pid, collection) do
    send client_pid, {:send, json!(%{msg: "sub", name: collection, id: id = UUID.uuid4})}
    { collection, id }
  end

  defp json!(map) do
    JSON.encode!(map) |> IO.iodata_to_binary
  end

  def send_json_message(client_pid, map) do
    send(client_pid, {:send, json!(map)})
  end
end
