
def deps
  require 'socket'
  require 'webrick'
  require 'logger'
end

begin
  deps
rescue
  Dir.chdir(__dir__) do
  `gem install bundler`
  `bundle`
  end
  deps
end

log = Logger.new('logs/requests.log')

server = TCPServer.new('0.0.0.0', 10_075)
puts "Server running on #{server.addr.last}:#{server.addr[1]}"

trap('INT') { puts 'Ciao!'; exit }

request_analyzer = lambda do |sock|
  config = WEBrick::Config::HTTP
  # config[:ServerSoftware] = 'Playcore Debug Server'
  res = WEBrick::HTTPResponse.new(config)
  req = WEBrick::HTTPRequest.new(config)
  req.parse(sock)
  puts 'Incoming request - reading the socket'
  puts '***'

  # Prepping the response
  res.request_method = req.request_method
  res.request_uri = req.request_uri
  res.request_http_version = req.http_version
  res.keep_alive = req.keep_alive?

  res.body << "Received request from #{req.remote_ip} (method: #{req.request_method} | version: #{req.http_version})\n"
  res.body << "Raw headers: #{req.raw_header}\n"
  res.body << "Parsed Headers: #{req.header}\n"
  res.body << "Cookies: #{req.cookies}\n"
  res.body << "Request uri: #{req.request_uri}\n"
  res.body << "path: #{req.path}\n"
  res.body << "Script name: #{req.script_name}\n"
  res.body << "Path info: #{req.path_info}\n"
  res.body << "Query string: #{req.query_string}\n"
  res.body << "Body: #{req.body}\n"
  res.body << "---\n"

  res.body << req.inspect
  res.body << "\n---\n"
  res.body << res.inspect
  res.body << "\n---\n"

  log.info(res.body)
  res.send_response(sock)
end

def display_header(socket)
  raw_header = ''.to_s
  while line = read_line(socket)
      break if /\A(#{WEBrick::CRLF}|#{WEBrick::LF})\z/om =~ line
      raw_header << line
  end
  raw_header
end

def _read_data(io, method, *arg)
    WEBrick::Utils.timeout(5) do
      return io.__send__(method, *arg)
    end
rescue Errno::ECONNRESET
    return nil
rescue TimeoutError
    puts 'Reading the data from the socket timed out'
end

def read_line(io, size = 4096)
  _read_data(io, :gets, WEBrick::LF, size)
end

# Serve the requests
begin
  while sock = server.accept_nonblock

    begin
      dup_sock = sock.dup
      request_analyzer.call(dup_sock)
    rescue Exception => e
      sock.print "FAIL\n"
      puts "Request parsing failed: #{e.inspect}"
      puts "Request Headers found:\n #{display_header(dup_sock)}"
      begin
        dup_sock.print "FAIL\n"
        sock.close
      rescue Exception => e
        puts "closing connection: #{e.inspect}"
      end
    ensure
      dup_sock.close rescue nil
    end

  end
rescue IO::WaitReadable, Errno::EINTR
  IO.select([server])
  retry
end
