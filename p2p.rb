require "thread"

Thread.abort_on_exception = true

module P2P  
  class BP
    def initialize(args)
      @args = args
      Thread.new do
        Connection.run
      end
    end
    
    def connect(trans, args)
      connection = Connection.new

      cb = args["callback"]      
      connection.on(:connnect)   {|port| cb.invoke(connection.id, "connnect", port) }
      connection.on(:data)       {|data| cb.invoke(connection.id, "data", data) }
      connection.on(:disconnect) {
        cb.invoke(connection.id, "disconnect") 
        trans.complete
      }
      
      connection.connect(
        args["local_port"], 
        args["host"], 
        args["port"]
      )
    end
    
    def accept(trans, args)      
      connection = Connection.new
      
      cb = args["callback"]
      connection.on(:connnect)   {       cb.invoke(connection.id, "connnect") }
      connection.on(:data)       {|data| cb.invoke(connection.id, "data",   data) }
      connection.on(:accept)     {|port| cb.invoke(connection.id, "accept", port) }
      connection.on(:disconnect) { 
        cb.invoke(connection.id, "disconnect") 
        trans.complete
      }
      
      connection.accept(
        args["local_port"], 
        args["host"], 
        args["port"]
      )
    end
    
    def disconnect(trans, args)
      connection = Connection.find(args["connection"])
      connection.disconnect
      trans.complete
    end
    
    def write(trans, args)
      connection = Connection.find(args["connection"])
      connection.write(
        args["path"] ? 
          args["path"].open("rb") : 
          StringIO.new(args["data"])
      )
      trans.complete
    end
  end
end

# If we are testing locally, bp_require
# is not defined, so we must alias it
unless defined?(bp_require)
  $: << File.expand_path(__FILE__)
  alias :bp_require :require
end

%w{ 
  p2p/events 
  p2p/connection 
  p2p/async_socket
  p2p/p2p_socket 
}.each {|lib| bp_require(lib) }

rubyCoreletDefinition = {
  "name"  => "P2P",
  "class" => "P2P::BP",
  "major_version" => 0, 
  "minor_version" => 0, 
  "micro_version" => 1, 
  "documentation" => "TCP P2P in the browser",
  "functions" => 
  [
    {
      "name" => "connect",
      "documentation" => "Connect to remote host",    
      "arguments" => [
        {
          "name" => "callback",
          "type" => "callback",    
          "documentation" => "Connection callback",    
          "required" => true    
        }, {
          "name" => "local_port",
          "type" => "integer",    
          "documentation" => "Local port",    
          "required" => true    
        }, {
          "name" => "host",
          "type" => "string",    
          "documentation" => "Host",    
          "required" => true    
        }, {
          "name" => "port",
          "type" => "integer",    
          "documentation" => "Port",    
          "required" => true    
        }
      ]
    },
    
    {
      "name" => "accept",
      "documentation" => "Connect to remote host",    
      "arguments" => [
        {
          "name" => "callback",
          "type" => "callback",    
          "documentation" => "Connection callback",    
          "required" => true    
        }, {
          "name" => "local_port",
          "type" => "integer",    
          "documentation" => "Local port",    
          "required" => false    
        }, {
          "name" => "host",
          "type" => "string",    
          "documentation" => "Host",    
          "required" => true    
        }, {
          "name" => "port",
          "type" => "integer",    
          "documentation" => "Port",    
          "required" => true    
        }
      ]
    },
    
    {
      "name" => "disconnect",
      "documentation" => "Connect to remote host",    
      "arguments" => [
        {
          "name" => "connection",
          "type" => "integer",    
          "documentation" => "Connection instance",    
          "required" => true    
        }
      ]
    },
    
    {
      "name" => "write",
      "documentation" => "Write to connection",    
      "arguments" => [
        {
          "name" => "connection",
          "type" => "integer",    
          "documentation" => "Connection instance",    
          "required" => true    
        }, {
          "name" => "path",
          "type" => "path",    
          "documentation" => "File path",    
          "required" => false
        }, {
          "name" => "data",
          "type" => "string",    
          "documentation" => "File data",    
          "required" => false
        }
      ]
    }
  ]
}