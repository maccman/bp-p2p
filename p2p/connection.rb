require "timeout"
require "thread"

module P2P
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
          to_read  = connections.map {|c| c.socket }
          to_write = to_read.select  {|s| s.pending_write? }
          readable, writeable = select(to_read, to_write)
          readable.each  {|r| r.notify_readable  } if readable
          writeable.each {|w| w.notify_writeable } if writeable
        end
      end
    end
    
    # Event types:
    # * :connect
    # * :disconnect
    # * :data
    # * :accept
    include Events
    
    attr_reader :socket
    
    def initialize
      @socket = P2PSocket.new
      @socket.on(:data,       method(:data))
      @socket.on(:disconnect, method(:disconnect))

      self.class.connections << self
    end
    
    def disconnect
      close 
      self.class.connections.delete(self)
      trigger :disconnect
    end
    
    def id
      self.class.connections.index(self)
    end
    
    # P2P methods
    
    def connect(local_port, host, port)
      socket.bind(local_port)
      socket.connect_nonblock(host, port)
      trigger :connect
    rescue Errno::ECONNREFUSED
    end
    
    def accept(local_port, host, port)
      # Bind to specificed port, or random
      socket.bind(local_port || 0)
      
      # Manage up to 5 streams
      socket.listen(5)
      
      # Get real bound port
      trigger :accept, socket.local_port
      
      # Send SYN packet to remote host,
      # opening up a hole in our firewall
      send_syn(host, port)
      
      # Close connection, and listen for
      # incoming connections
      close
      @socket, _ = socket.accept_nonblock
      trigger :connect
    rescue Timeout::Error
    end
    
    protected
      def data(body)
        trigger :data, body
      end
    
      def close
        socket.close unless socket.closed?
      end
    
      def send_syn(host, port)
        # If we open and close a socket 
        # really quickly, all that gets
        # transmitted is a SYN packet
        Timeout::timeout(0.3) do
          socket.connect(host, port)
        end
      rescue Timeout::Error
      rescue # Errno errors
      end
  end
end