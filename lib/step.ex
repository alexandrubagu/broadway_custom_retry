defmodule BroadwayRabbitMQCustomRetry.Step do
  @moduledoc false

  use Broadway

  alias Broadway.Message

  @queue "my_queue"
  @exchange "my_exchange"
  @queue_dlx "my_queue.dlx"
  @exchange_dlx "my_exchange.dlx"

  @delay_header_name "x-delay"
  @retry_header "x-retries"
  @max_retries 10

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          BroadwayRabbitMQ.Producer,
          on_failure: :reject,
          after_connect: &declare_rabbitmq_topology/1,
          queue: @queue,
          declare: [
            durable: true,
            arguments: [
              {"x-dead-letter-exchange", :longstr, @exchange_dlx},
              {"x-dead-letter-routing-key", :longstr, @queue_dlx}
            ]
          ],
          bindings: [{@exchange, []}],
          metadata: [:headers]
        },
        concurrency: 2
      ],
      processors: [default: [concurrency: 4]]
    )
  end

  defp declare_rabbitmq_topology(amqp_channel) do
    with :ok <- AMQP.Exchange.declare(amqp_channel, @exchange, :direct, durable: true),
         :ok <- AMQP.Exchange.declare(amqp_channel, @exchange_dlx, :direct, durable: true),
         {:ok, _} <- AMQP.Queue.declare(amqp_channel, @queue_dlx, durable: true),
         :ok <- AMQP.Queue.bind(amqp_channel, @queue_dlx, @exchange_dlx) do
      :ok
    end
  end

  @impl true
  def handle_message(
        _processor,
        %Message{data: data, metadata: %{headers: headers, amqp_channel: amqp_channel}} = message,
        _context
      ) do
    retry_data = %{retry_count: retry_count, index: _index} = get_retry_count(headers)

    if retry_count <= @max_retries do
      updated_headers =
        headers
        |> update_retry_count(retry_data)
        |> update_retry_delay()

      IO.inspect("retry: #{retry_count}")

      case AMQP.Basic.publish(amqp_channel, @exchange, "", data, headers: updated_headers) do
        :ok -> message
        error -> IO.inspect("#{inspect(error)}")
      end
    else
      Message.failed(message, "Message reached max retries of #{@max_retries}")
    end
  end

  def get_retry_count(headers) do
    Enum.reduce_while(headers, %{retry_count: 1, index: -1}, fn {name, _type, value},
                                                                %{index: index} = acc ->
      if name == @retry_header do
        acc =
          acc
          |> Map.put(:retry_count, value)
          |> Map.put(:index, index + 1)

        {:halt, acc}
      else
        acc = Map.put(acc, :index, index + 1)

        {:cont, acc}
      end
    end)
  end

  defp update_retry_count(headers, %{retry_count: _, index: -1}) do
    [{@retry_header, :long, 1} | headers]
  end

  defp update_retry_count(headers, %{retry_count: retry_count, index: index}) do
    List.update_at(headers, index, fn {@retry_header, :long, ^retry_count} ->
      {@retry_header, :long, retry_count + 1}
    end)
  end

  defp update_retry_delay(headers) do
    delay_index =
      Enum.find_index(headers, fn {name, _, _} ->
        name == @delay_header_name
      end)

    if delay_index == nil do
      IO.puts("First delay set to #{200} ms")
      [{@delay_header_name, :signedint, 200} | headers]
    else
      List.update_at(headers, delay_index, fn {@delay_header_name, type, value} ->
        # after the delayed exchange processes the delayed message, the exchange negates the delayed value
        # the negation is how you can determine the message had been delayed before
        # must get absolute value then increase the delay by a multiple of 3.
        # Ex delay: 100 ms, 300 ms, 900 ms, 2.7 seconds, 8.1 seconds, etc.

        delay = abs(value) * 3
        IO.puts("Delay set to #{delay} ms")
        {@delay_header_name, type, delay}
      end)
    end
  end
end
