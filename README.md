# Chord Protocol

**The program implements Chord Protocol. It takes the number of nodes and number of requests as input. The average hop count is calculated for every request and is given as output.**

## Group Info

UFID: 8115-5459 Shaileshbhai Revabhai Gothi


UFID: 8916-9425 Sivani Sri Sruthi Korukonda

## Instructions

To run the code for this project, simply run in your terminal:

```elixir
$ mix compile
$ iex -S mix
$ iex main = CHORD.Main.start_link(<noOfNodes>,<noOfRequests>,<noOfBits>,<bonus>)
<noOfBits> and <bonus> are optional. The default number of bits are 32 and bonus is false
$ iex GenServer.cast(<mainPid>,{:startQuery})
```
Example:
```elixir
$ mix compile
$ iex -S mix
$ iex main = CHORD.Main.start_link(100,10)
$ iex GenServer.cast(elem(main,1),{:startQuery})
```

For bonus part:

```elixir
$ mix compile
$ iex -S mix
$ iex main = CHORD.Main.start_link(100,10,32,true)
$ iex GenServer.cast(elem(main,1),{:startQuery})
To kill a random node :
$ iex GenServer.stop(:global.whereis_name(<printedNodeIdString>, :normal) 
We are printing the list of node ids in console, you can pick any one of the node ids as the printedNodeIdString
```


## Tests

To run the tests for this project, simply run in your terminal:

```elixir
$ mix test
```

## What is working

We can form a chord ring by giving the number of nodes and number of requests. The finger table of the nodes is calculated and is updated periodically.
Please check **Report.pdf** for additional information.

## Largest Network implemented:

The largest network implemented is 10000 nodes with 10 requests within a minute.

## Documentation

To generate the documentation, run the following command in your terminal:

```elixir
$ mix docs
```
This will generate a doc/ directory with a documentation in HTML. 
To view the documentation, open the index.html file in the generated directory.



