require "socket"

module P2P
  module AsyncSocket
    def self.included(base)
      base.send :include, Events
    end
        
    def write(io)
      while buffer = io.read(4096)
        write_queue.push(buffer)
      end
    end
    
    def notify_readable
      trigger(:data, read_nonblock(1024))
    rescue EOFError
      trigger :disconnect
    end
    
    def notify_writeable
      if write_queue.any?
        write_nonblock(write_queue.shift)
      end
    end
    
    def pending_write?
      write_queue.any?
    end
    
    protected
      def write_queue
        @write_queue ||= []
      end
  end
  
  # Patch Async into Socket
  Socket.send(:include, AsyncSocket)
end