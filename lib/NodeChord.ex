defmodule CHORD.NodeChord do
  use GenServer
  require Logger

  @moduledoc """
  Calculates the finger table of every node and keeps updating it.
  """
  @doc """
  Starts the GenServer.
  """
  def start_link(inputs, name) do
    GenServer.start_link(__MODULE__, inputs, name: {:global, name})
  end

  @doc """
  Initiates the state of the GenServer.
  """
  def init(inputs) do
    state = init_state(inputs)
    {:ok, state}
  end

  @doc """
  Returns `{fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq, next}`
  """
  def init_state(inputs) do
    predecessor = elem(inputs,3)
    mbits = elem(inputs, 4)
    successor = elem(inputs, 2)
    nodeIdList = elem(inputs, 0)
    nodeIndex = elem(inputs, 1)
    noOfReq = elem(inputs, 5)
    nodeId = elem(nodeIdList, nodeIndex)
    key = nodeId
    fingerTable = initializeFingerTable(nodeId, mbits, nodeIdList, nodeIndex)
    completedReqHopCount = []
    next = 0
    bonus = elem(inputs, 6)
    if(bonus) do
      Process.send_after(self(), :stabilize, 1000)
      Process.send_after(self(), :fixFingerTable, 1000)
    end
    {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq, next}
  end

  defp convertToHex(num, mbits) do
    hexNumber = Integer.to_string(num, 16)
    # prepending 0 to have similar ids
    difference = div(mbits, 4) - String.length(hexNumber)

    hex =
      if difference <= 0 do
        hexNumber
      else
        Enum.reduce(1..difference, hexNumber, fn _, acc -> "0" <> acc end)
      end

    hex
  end

  defp convertToInt(num) do
    elem(Integer.parse(num, 16), 0)
  end

  @doc """
  Creates the FingerTable with nodeId and successor
  """
  def initializeFingerTable(nodeId, mbits, nodeIdList, nodeIndex) do
    fingerTable =
      Enum.reduce(0..(mbits - 1), %{}, fn index, acc ->
        # Convert hex string to integer and add 2 pow i
        newNodeId =
          rem(
            convertToInt(nodeId) + Kernel.trunc(:math.pow(2, index)),
            Kernel.trunc(:math.pow(2, mbits))
          )

        nextNode = findFingerNode(nodeIdList, nodeIndex, newNodeId, mbits)
        Map.put(acc, index, nextNode)
      end)

    fingerTable
  end

  defp findFingerNode(nodeList, index, key, mbits) do
    previousNodeId =
      if index == 0 do
        # return the last node
        convertToInt(elem(nodeList, tuple_size(nodeList) - 1))
      else
        # return previous node
        convertToInt(elem(nodeList, index - 1))
      end

    # Logger.info("previousNodeId #{inspect(previousNodeId)}")
    currentNodeId = convertToInt(elem(nodeList, index))
    # Logger.info("currentNodeId #{inspect(currentNodeId)}")
    fingerNodeId =
      cond do
        index == 0 && (key > previousNodeId || key < currentNodeId) ->
          elem(nodeList, 0)

        index != 0 && index < tuple_size(nodeList) && key > previousNodeId && key <= currentNodeId ->
          convertToHex(currentNodeId, mbits)

        true ->
          index = rem(index + 1, tuple_size(nodeList))
          findFingerNode(nodeList, index, key, mbits)
      end

    fingerNodeId
  end

  @doc """
  Called when a new node enters.
  Passing a knownNode from the ring.
  """
  def handle_cast(
        {:join, knownNode},
        {fingerTable, predecessor, _, mbits, nodeId, key, completedReqHopCount, noOfReq, next}
      ) do
    successor = GenServer.call(knownNode, {:findFingerNode, nodeId})
    GenServer.call(self(), {:notify, successor})

    {:noreply,
     {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
      next}}
  end

  @doc """
  Returns '{predecessor}'
  """
  def handle_cast(
        {:getPredecessor, reqNodeId},
        {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
         next}
      ) do
        GenServer.cast({:global, reqNodeId}, {:afterPredecessorAvailable, predecessor})
    {:noreply,
     {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
      next}}
  end

  def handle_cast(
        {:afterPredecessorAvailable, nextNodePredecessor},
        {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
         next}
      ) do
        # after predecessor is available proceed with stabilization phase.
        nextNodePredecessorInt = convertToInt(nextNodePredecessor)
        successorInt = convertToInt(successor)
        nodeIdInt = convertToInt(nodeId)
        predecessorRelative = computeRelative(nextNodePredecessorInt, nodeIdInt, mbits)
        successorRelative = computeRelative(successorInt, nodeIdInt, mbits)

        newSuccessor =
          if predecessorRelative > 0 && successorRelative <= successorRelative do
            nextNodePredecessor
          else
            successor
          end
        if(:global.whereis_name(newSuccessor) != :undefined) do
          # Notify the successor if it is alive
          GenServer.cast({:global, newSuccessor}, {:notify, nodeId})
        end
    {:noreply,
     {fingerTable, predecessor, newSuccessor, mbits, nodeId, key, completedReqHopCount, noOfReq,
      next}}
  end

  @doc """
  Updates the predecessor of the NewNode's successor.
  """
  def handle_cast(
        {:notify, newPredecessor},
        {fingerTable, _, successor, mbits, nodeId, key, completedReqHopCount, noOfReq, next}
      ) do
    {:noreply,
     {fingerTable, newPredecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
      next}}
  end

  @doc """
  Finds successor periodically and refreshes the Fingertable
  """
  def handle_info(
        :fixFingerTable,
        {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
         next}
      ) do
    next = next + 1

    next =
      if(next > mbits) do
        1
      else
        next
      end

    newnodeId = convertToInt(nodeId) + Kernel.trunc(:math.pow(2, next - 1))
    newnodeId = convertToHex(newnodeId, mbits)
    GenServer.cast({:global, nodeId}, {:findSuccessor, newnodeId, nodeId, 0, true, next, false})
    Process.send_after(self(), :fixFingerTable, 1000)

    {:noreply,
     {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
      next}}
  end

  @doc """
  Stabilizes the Chord ring perodically by updating the values
  of successor and notifying successor to update perdecessor
  """
  def handle_info(
        :stabilize,
        {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
         next}
      ) do
      if(:global.whereis_name(successor) == :undefined) do
        GenServer.cast({:global, nodeId}, {:findSuccessor, nodeId, nodeId, 0, false, 0, true})
      else
        # Async Get predecessor of successor and do processing after it is available.
        # Sync getting was blocking all the nodes
        GenServer.cast({:global, successor},{:getPredecessor, nodeId})
      end

    Process.send_after(self(), :stabilize, 1000)

    {:noreply,
     {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
      next}}
  end

  @doc """
  Finds successor of every node.
  Calculates the hop count for every request.
  """
  def handle_cast(
        {:findSuccessor, nodeIdToFind, startingNode, hopCount, bFixFinger, index, bStabilize},
        {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
         next}
      ) do
    nodeIdToFindInt = convertToInt(nodeIdToFind)
    nodeIdInt = convertToInt(nodeId)
    successorInt = convertToInt(successor)
    findRelativeId = computeRelative(nodeIdToFindInt, nodeIdInt, mbits)
    successorRelativeId = computeRelative(successorInt, nodeIdInt, mbits)

    if findRelativeId > 0 && findRelativeId < successorRelativeId do
      # Inform the node which started the search that key is found
      GenServer.cast(
        {:global, startingNode},
        {:searchCompleted, successor, hopCount, bFixFinger, index, bStabilize}
      )
    else
      hopCount = hopCount + 1
      nearesetNode = closestPrecedingNode(nodeIdInt, nodeIdToFindInt, mbits, fingerTable)
      # Query the successor Node for the key.
      GenServer.cast(
        {:global, nearesetNode},
        {:findSuccessor, nodeIdToFind, startingNode, hopCount, bFixFinger, index, bStabilize}
      )
    end

    {:noreply,
     {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
      next}}
  end

  @doc """
  Finds the highest predecessor of the nodeId from the finger table
  """
  def closestPrecedingNode(nodeIdInt, nodeIdToFindInt, mbits, fingerTable) do
    foundNodeId =
      Enum.reduce_while((mbits - 1)..0, 0, fn mapKey, _ ->
        if Map.has_key?(fingerTable, mapKey) do
          fingerNodeInt = convertToInt(fingerTable[mapKey])
          findIdRelative = computeRelative(nodeIdToFindInt, nodeIdInt, mbits)
          fingerIdRelative = computeRelative(fingerNodeInt, nodeIdInt, mbits)

          if fingerIdRelative > 0 && fingerIdRelative < findIdRelative do
            if(:global.whereis_name(fingerTable[mapKey]) != :undefined) do
              {:halt, fingerTable[mapKey]}
            end
          else
            {:cont, fingerTable[mbits - 1]}
          end
        else
          {:cont, fingerTable[mbits - 1]}
        end
      end)

    foundNodeId
  end

  defp computeRelative(num1, num2, mbits) do
    ret = num1 - num2

    ret =
      if(ret < 0) do
        ret + Kernel.trunc(:math.pow(2, mbits))
      else
        ret
      end

    ret
  end

  @doc """
  Random keys are generated based on number of requests
  Search for the keys in the chord ring
  """
  def handle_cast(
        {:searchKeys},
        {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
         next}
      ) do
    Enum.each(0..(noOfReq - 1), fn _ ->
      randomKey = generateRandomKey(mbits)
      GenServer.cast({:global, nodeId}, {:findSuccessor, randomKey, nodeId, 0, false, 0, false})
      Process.sleep(1000)
    end)

    {:noreply,
     {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
      next}}
  end

  defp generateRandomKey(mbits) do
    aIpAddr = [:rand.uniform(255), :rand.uniform(255), :rand.uniform(255), :rand.uniform(255)]
    hashKey = aIpAddr |> Enum.join(":")
    hashKey = :crypto.hash(:sha, hashKey) |> Base.encode16()

    hashKey =
      String.slice(hashKey, (String.length(hashKey) - div(mbits, 4))..String.length(hashKey))

    hashKey
  end

  @doc """
  Calculates average hop count when all the requested keys are found.
  """
  def handle_cast(
        {:searchCompleted, newSuccessor, hopCount, bFixFinger, index, bStabilize},
        {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
         next}
      ) do
    completedReqHopCount = completedReqHopCount ++ [hopCount]
    # Update the finger table if find Successor was trigerred by fixFingers
    fingerTable =
      if(bFixFinger) do
        Map.put(fingerTable, index, newSuccessor)
      else
        fingerTable
      end

    # Update the successor if findsuccessor was initiated by Stabilize when successor is dead
    successor =
      if(bStabilize) do
        newSuccessor
      else
        successor
      end

    if(length(completedReqHopCount) == noOfReq) do
      avgHop = Enum.sum(completedReqHopCount) / noOfReq
      GenServer.cast(:genMain, {:completedReq, nodeId, avgHop})
    end

    {:noreply,
     {fingerTable, predecessor, successor, mbits, nodeId, key, completedReqHopCount, noOfReq,
      next}}
  end
end
