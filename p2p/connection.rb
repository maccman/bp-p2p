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
          sockets  = self.connections.select {|c| c.select? }
          sockets  = sockets.map {|s| s.socket }
          
          to_read  = sockets
          to_write = to_read.select {|s| s.pending_write? }
          
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
    attr_writer :select
    
    def initialize
      self.select = false
      self.class.connections << self
    end
    
    def id
      self.class.connections.index(self)
    end
    
    # P2P methods

    def connect(local_port, host, port)
      socket.bind(local_port)
      
      Timeout::timeout(5) do
        socket.connect(host, port)
      end
      
      connected
    rescue Errno::ECONNREFUSED, Timeout::Error
      disconnected
    end
    
    def accept(local_port, host, port)
      # Bind to specificed port, or random
      socket.bind(local_port || 0)
      
      # Manage up to 5 streams
      socket.listen(5)
      
      # Get real bound port
      trigger :bind, socket.local_port
      
      # Send SYN packet to remote host,
      # opening up a hole in our firewall
      send_syn(host, port)
      
      # Close connection, and listen for
      # incoming connections
      close
      
      # Accept an incoming connection,
      # and swap it with the current
      # socket instance
      Timeout::timeout(5) do
        session, _ = socket.accept
        session.event_store = socket.event_store
        @socket = session
      end
      
      connected
    rescue Timeout::Error
      disconnected
    end
    
    def select?
      @select && @socket
    end
    
    def disconnect
      close_socket
    end
    
    def socket
      @socket ||= begin
        sock = SocketP2P.new
        sock.on(:data,       method(:data))
        sock.on(:disconnect, method(:disconnected))
        sock
      end
    end
    
    protected
      def disconnected
        self.select = false
        close_socket
        self.class.connections.delete(self)
        trigger :disconnect
      end
    
      def connected
        self.select = true
        trigger :connect
      end
      
      def close_socket
        return unless self.socket
        self.socket.close unless self.socket.closed?
      end
    
      def data(body)
        trigger :data, body
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