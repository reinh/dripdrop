require 'thin'
require 'json'

class DripDrop
  class HTTPDeferrableBody
    include EventMachine::Deferrable
    
    def call(body)
      body.each do |chunk|
        @body_callback.call(chunk)
      end
    end

    def each(&blk)
      @body_callback = blk
    end
    
    def send_message(msg)
      if msg.class == DripDrop::Message
        json = msg.encode_json
        self.call([json])
        self.succeed
      else
        raise "Message Type not supported"
      end
    end
  end
  
  class HTTPApp
    AsyncResponse = [-1, {}, []].freeze
    
    def initialize(msg_format,&block)
      @msg_format = msg_format
      @recv_cbak  = block
      super
    end
    
    def call(env)
      body = HTTPDeferrableBody.new
      
      EM.next_tick do
        env['async.callback'].call([200, {'Content-Type' => 'text/plain'}, body])
        EM.next_tick do
          case @msg_format
          when :dripdrop_json
            msg = DripDrop::Message.decode_json(env['rack.input'].read)
            begin
              @recv_cbak.call(body,msg)
            rescue StandardError => e
              puts e.inspect
                puts e.backtrace.join("\n")
              end
          else
            raise "Unsupported message type #{@msg_format}"
          end
        end
      end
       
      AsyncResponse
    end
  end
  
  class HTTPServerHandler
    attr_reader :address, :opts
    
    def initialize(address,opts={})
      @address = address
      @opts    = opts
    end

    def on_recv(msg_format=:dripdrop_json,&block)
      @app = HTTPApp.new(msg_format,&block)
      Thin::Server.start(@address.host, @address.port,@app)
    end
  end

  class HTTPClientHandler
    attr_reader :address, :opts
    
    def initialize(address, opts={})
      @address = address
      @opts    = opts
    end
    
    def send_message(msg,&block)
      if msg.class == DripDrop::Message
        req = EM::Protocols::HttpClient.request(
          :host => address.host, :port => address.port,
          :request => '/', :verb => 'POST',
          :contenttype => 'application/json',
          :content => msg.encode_json
        )
        req.callback do |response|
          block.call(DripDrop::Message.decode_json(response[:content]))
        end
      else
        raise "Unsupported message type '#{msg.class}'"
      end
    end
  end
end
