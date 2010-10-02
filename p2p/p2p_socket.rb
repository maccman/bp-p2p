require "socket"

Socket.do_not_reverse_lookup = true

module P2P
  class P2PSocket < Socket
    def initialize
      super(AF_INET, SOCK_STREAM, 0)
      
      # Re-use address and port if at all possible.
      # Usually, TCP doesn't let you do this, 
      # for security reasons.
      setsockopt(SOL_SOCKET, SO_REUSEADDR, 1)
      if defined?(SO_REUSEPORT)
        setsockopt(SOL_SOCKET, SO_REUSEPORT, 1)
      end
      
      # Needed for Windows support
      binmode
    end
    
    # Bind to local port, defaulting 
    # to a system choice
    def bind(port = 0)
      addr_local = Socket.pack_sockaddr_in(port, "0.0.0.0")
      super(addr_local)
    end
    
    def connect(host, port)
      addr_remote = Socket.pack_sockaddr_in(port, host)
      super(addr_remote)
    end
    
    def addr
      Socket.unpack_sockaddr_in(getsockname)
    end
    
    def local_port
      addr[0]
    end
  end
end