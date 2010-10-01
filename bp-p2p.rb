require "socket"
require "timeout"

module PeerToPeer  
  module Events
    def event_store
      @event_store ||= {}
    end
    
    def on(name, method)
      event_store[name] ||= []
      event_store[name] << method
    end
    
    def trigger(name, *data)
      event_store[name] ||= []
      event_store[name].each {|e| e.call(*data) }
    end
    
    def events(*names)
      names.each do |name|
        class_eval(<<-EOS, __FILE__, __LINE__ + 1)
          def #{name}(*args, &block)
            method = block || args[0]
            method.respond_to?(:call) ? bind(:#{name}, *args) : trigger(:#{name}, *args)
          end
        EOS
      end
    end
  end
  
  class P2PSocket < Socket
    def initialize
      super(AF_INET, SOCK_STREAM, 0)
      setsockopt(SOL_SOCKET, SO_REUSEADDR, 1)
      if defined?(SO_REUSEPORT)
        setsockopt(SOL_SOCKET, SO_REUSEPORT, 1)
      end
      binmode
    end
    
    def bind(port = 0)
      addr_local = Socket.pack_sockaddr_in(port, "0.0.0.0")
      super(addr_local)
    end
    
    def connect(host, port)
      addr_remote = Socket.pack_sockaddr_in(port, host)
      super(addr_remote)
    end
    
    def accept
      super[0]
    end
    
    def addr
      Socket.unpack_sockaddr_in(getsockname)
    end
    
    def local_port
      addr[0]
    end
  end
  
  class Connection
    class << self
      def connections
        @@connections ||= []
      end
      
      def find(id)
        connections[id] || raise("Unknown connection")
      end
      
      def run
        loop do
          to_read  = connections
          to_write = connections.select {|c| c.pending_write? }
          readable, writeable = select(to_read, to_write)
          readable.each  {|r| r.notify_readable  } if readable
          writeable.each {|w| w.notify_writeable } if writeable
        end
      end
    end
    
    include Events
    events :connect, :disconnect, :data
    
    attr_reader :socket
    attr_writer :connected
    
    def initialize
      @socket = Socket.new
      self.class.connections << self
      @write_queue = []
    end
    
    def disconnect
      close 
      self.class.connections.delete(self)
      trigger :disconnect
    end
    
    def id
      self.class.connections.index(self)
    end
    
    def addr
      socket.addr
    end
    
    # P2P methods
    
    def connect(local_port, host, port)
      socket.bind(local_port)
      socket.connect(host, port)
    rescue Timeout::Error
    rescue Errno::ECONNREFUSED
    end
    
    def accept(local_port, host, port)
      socket.bind(local_port || 0)
      socket.bind(5)
      send_syn(host, port)
      close
      socket.accept_nonblock
      trigger :connect, socket.local_port
    rescue Timeout::Error
    end
    
    # Async methods
    
    def write(io)
      while buffer = io.read(4096)
        @write_queue.push(buffer)
      end
    end
    
    def notify_readable
      trigger(:data, read_nonblock(1024))
    rescue EOFError
      disconnect
    end
    
    def notify_writeable
      if @write_queue.any?
        socket.write_nonblock(@write_queue.shift)
      end
    end
    
    def pending_write?
      @write_queue.any?
    end
    
    protected
      def close
        socket.close unless socket.closed?
      end
    
      def send_syn(host, port)
        Timeout::timeout(0.3) do
          socket.connect(host, port)
        end
      rescue Timeout::Error
      rescue # Errno errors
      end
  end
  
  class BP
    def initialize(args)
      @args = args
    end
    
    def connect(trans, args)
      cb = args["callback"]      
      connection = Connection.new
      connection.on(:connnect)   {|port| cb.invoke(connection.id, "connnect", port) }
      connection.on(:data)       {|data| cb.invoke(connection.id, "data", data) }
      connection.on(:disconnect) {       cb.invoke(connection.id, "connnect") }
      connection.connect(args["local_port"], args["host"], args["port"])
    end
    
    def accept(trans, args)
      cb = args["callback"]
      connection = Connection.new
      connection.on(:connnect)   {|port| cb.invoke(connection.id, "connnect", port) }
      connection.on(:data)       {|data| cb.invoke(connection.id, "data", data) }
      connection.on(:disconnect) {       cb.invoke(connection.id, "connnect") }
      connection.accept(args["local_port"], args["host"], args["port"])
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
    
    def addr(trans, args)
      connection = Connection.find(args["connection"])
      trans.complete(connection.addr)
    end
  end
end

rubyCoreletDefinition = {
  "name"  => "PeerToPeer",
  "class" => "PeerToPeer::BP",
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
    },
    
    {
      "name" => "addr",
      "documentation" => "Get address info",    
      "arguments" => [
        {
          "name" => "connection",
          "type" => "integer",    
          "documentation" => "Connection instance",    
          "required" => true    
        }
      ]
    }
  ]
}