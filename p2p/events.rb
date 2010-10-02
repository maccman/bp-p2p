module P2P  
  module Events
    def event_store
      @event_store ||= {}
    end
    
    def on(name, method = nil, &block)
      event_store[name] ||= []
      event_store[name] << (method||block)
    end
    
    def trigger(name, *data)
      event_store[name] ||= []
      event_store[name].each {|e| e && e.call(*data) }
    end
  end
end