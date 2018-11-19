defmodule CHORD.Main do
  require Logger
  @moduledoc """
  Creates chord ring based on number of nodes.
  Starts the search for the requested keys.
  """
  @doc """
  Starts the GenServer.
  """
  def start_link(noOfNodes, numofReq, mbits \\ 32, bonus \\ false) do
    GenServer.start_link(__MODULE__, {noOfNodes, numofReq, mbits, bonus}, name: :genMain)
  end

  @doc """
  Initiates the state of the GenServer.
  """
  def init(inputs) do
    state = init_state(inputs)
    {:ok, state}
  end

  defp init_state(inputs) do
    noOfNodes = elem(inputs, 0) || 5
    numofReq = elem(inputs, 1)
    mbits = elem(inputs,2)
    bonus = elem(inputs,3)
    completedNodes = %{}
    nodes = createChordRing(noOfNodes, numofReq, bonus, mbits)
    {noOfNodes, numofReq, nodes, completedNodes, mbits}
  end

  defp createChordRing(noOfNodes, numofReq, bonus, mbits) do
    # get sorted list of all nodeIds so we can form initial ring
    nodeIdTuple = getnodeIdTuple(noOfNodes, mbits)
    Enum.each(0..noOfNodes-1, fn index->
      # Node id is present at currenct index and Successor is (next index)% noOfNodes in list
      nodeId = elem(nodeIdTuple,index)
      previousIndex = if(index-1 <0) do
        tuple_size(nodeIdTuple)-1
      else
        index-1
      end
      CHORD.NodeChord.start_link({nodeIdTuple, index, elem(nodeIdTuple,rem(index+1,noOfNodes)), elem(nodeIdTuple,rem(previousIndex,noOfNodes)), mbits, numofReq, bonus}, nodeId)
    end)
    Logger.info("Initial Chord Ring Created")
    nodeIdTuple
  end


  defp createRandomIpAddress() do
    aIpAddr = [:rand.uniform(255), :rand.uniform(255),:rand.uniform(255),:rand.uniform(255)]
    aIpAddr |> Enum.join(":")
  end

  defp findUniqueHash(mbits, nodeTuple) do
    nodeId = :crypto.hash(:sha, createRandomIpAddress()) |> Base.encode16
    # Take last m bits from the hash string
    nodeId = String.slice(nodeId, (String.length(nodeId) - div(mbits,4))..String.length(nodeId))
    nodeList = Tuple.to_list(nodeTuple)
    uniqueNodeId =if (Enum.member?(nodeList,nodeId)) do
      findUniqueHash(mbits,nodeTuple)
    else
      nodeId
    end
    uniqueNodeId
  end

  defp getnodeIdTuple(noOfNodes, mbits) do
    nodeIdTuple = Enum.reduce(1..noOfNodes,{}, fn _, acc ->
      uniqueNodeId = findUniqueHash(mbits,acc)
      acc = Tuple.append(acc,uniqueNodeId)
    end)
    nodeIdList = Tuple.to_list(nodeIdTuple)
    nodeIdList = Enum.sort(nodeIdList)
    nodeIdTuple = List.to_tuple(nodeIdList)
    IO.inspect nodeIdTuple
    nodeIdTuple
  end


  defp initiateSearchKeysForAllNodes(nodeIdTuple) do
    Enum.each(Tuple.to_list(nodeIdTuple), fn nodeId ->
      GenServer.cast({:global, nodeId}, {:searchKeys})
    end)
  end

  @doc """
  Starts searching for the keys
  """
  def handle_cast({:startQuery},{noOfNodes, numofReq, nodes, completedNodes, mbits}) do
    initiateSearchKeysForAllNodes(nodes)
    {:noreply,{noOfNodes, numofReq, nodes, completedNodes, mbits}}
  end

  @doc """
  Keeps track of the nodes which found the keys
  """
  def handle_cast({:completedReq, nodeId, avgHop}, {noOfNodes, numofReq, nodes, completedNodes, mbits}) do
    completedNodes = Map.put(completedNodes, nodeId, avgHop)
    if map_size(completedNodes) == noOfNodes do
      Logger.info("Completed chord search #{inspect(completedNodes)}")
    end
    {:noreply,{noOfNodes, numofReq, nodes, completedNodes, mbits}}
  end
end
