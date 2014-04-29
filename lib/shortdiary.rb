# Shortdiary API Ruby bindings

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'net/http'
require 'json'
require 'date'

API_ROOT = 'https://api.shortdiary.me/api/v1'

module Shortdiary

	class Error < StandardError; end
	class MissingDataError < StandardError; end
	class ServerError < StandardError; end
	class AuthenticationError < ServerError; end

	class Post
		attr_accessor :api, :text, :public_text, :mood, :date, :id, \
			:location_verbose, :location_lat, :location_lon, :public

		def initialize(*args)
			# Should probably use a hash here
			@api = args[0]
		end

		def attrs
			instance_variables.map{|ivar| instance_variable_get ivar}
		end

		def to_s
			return @text if @text.is_a?(String)
			''
		end

		def for_today?
			@date == Date.today
		end

		def save
			if not @text or not @date or not @mood
				raise MissingDataError
			end

			post_data = {
				:date => @date.to_s,
				:text => @text,
				:mood => @mood,
			}

			if @id
				new_post = @api.send_request("posts/#{@id}/", 'PUT', post_data)
			else
				new_post = @api.send_request("posts/", 'POST', post_data)
				@id = new_post['id']
			end
		end
	end

	class API
		def handle_server_error(res)
			begin
				json_data = JSON.parse res.body
			rescue JSON::ParserError
				raise ServerError, res.body
			end

			raise AuthenticationError if res.is_a?(Net::HTTPUnauthorized)
			raise ServerError, json_data['Error'] if json_data['Error']

			# Fallback
			raise ServerError, res.body
		end

		# Todo open one permanent connection and keep it alive
		def send_request(api_endpoint, type = 'GET', data = {})
			# Note: All 'real' API applications should probably use OAuth instead…
			uri = URI("#{API_ROOT}/#{api_endpoint}")
			
			case type
				when 'POST' then req = Net::HTTP::Post.new(uri)
				when 'PUT' then req = Net::HTTP::Put.new(uri)
				else req = Net::HTTP::Get.new(uri)
			end
			
			req.set_form_data(data) if type != 'GET'
			req.basic_auth(@username, @password)

			res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') {|http|
				http.request(req)
			}

			handle_server_error(res) if not res.is_a?(Net::HTTPSuccess)
			JSON.parse res.body
		end

		def get_request(api_endpoint)
			send_request(api_endpoint, 'GET')
		end

		def post_request(api_endpoint, data)
			send_request(api_endpoint, 'POST', data)
		end

		def put_request(api_endpoint, data)
			send_request(api_endpoint, 'PUT', data)
		end

		def initialize(*args)
			@username = args[0]
			@password = args[1]

			# Send & discard request to check login credentials
			get_request('posts/1/')

			nil
		end

		# Should probably be part of the Post class
		def format_post(raw_post)
			post = Post.new

			# Not pretty, but it does the job.
			raw_post.keys.select{ |key, _|
				begin
					post.send("#{key}=", raw_post[key])
				rescue NoMethodError; end
			}

			post.date = Date.strptime(raw_post['date'], '%Y-%m-%d')
			post.api = self
			post
		end

		# This doesn't really make any sense at all
		def new_post()
			created_post = Post.new
			created_post.api = self
			created_post
		end

		def posts()
			raw_posts = get_request('posts/')
			api_posts = []

			raw_posts.each {|raw_post|
				api_posts << format_post(raw_post)
			}

			api_posts
		end

		def get_post_for(date)
			# The API endpoint should allow filtering.
			posts.select {|post| post.date == date }[0]
		end

		def random_public()
			post = get_request('public/')
			format_post(post)
		end
	end

end
