require 'uri'
require 'net/http'
require 'net/https'

module ChefVPCToolkit

module HttpUtil

MULTI_PART_BOUNDARY="jtZ!pZ1973um"

def self.file_upload(url_string, file_data={}, post_data={}, auth_user=nil, auth_password=nil)
	url=URI.parse(url_string)
	http = Net::HTTP.new(url.host,url.port)
	req = Net::HTTP::Post.new(url.path)

	post_arr=[]
	post_data.each_pair do |key, value|
		post_arr << "--#{MULTI_PART_BOUNDARY}\r\n"
		post_arr << "Content-Disposition: form-data; name=\"#{key}\"\r\n"
		post_arr << "\r\n"
		post_arr << value
		post_arr << "\r\n"
	end

	file_data.each_pair do |name, file|
		post_arr << "--#{MULTI_PART_BOUNDARY}\r\n"
		post_arr << "Content-Disposition: form-data; name=\"#{name}\"; filename=\"#{File.basename(file)}\"\r\n"
		post_arr << "Content-Type: text/plain\r\n"
		post_arr << "\r\n"
		post_arr << File.read(file)
		post_arr << "\r\n--#{MULTI_PART_BOUNDARY}--\r\n"
	end
	post_arr << "--#{MULTI_PART_BOUNDARY}--\r\n\r\n"

	req.body=post_arr.join

	if url_string =~ /^https/
		http.use_ssl = true
		http.verify_mode = OpenSSL::SSL::VERIFY_NONE
	end
	req.basic_auth auth_user, auth_password if auth_user and auth_password
	req["Content-Type"] = "multipart/form-data, boundary=#{MULTI_PART_BOUNDARY}"

	response = http.request(req)
	case response
	when Net::HTTPSuccess
		return response.body
	else
		puts response.body
		response.error!
	end
end

def self.post(url_string, post_data, auth_user=nil, auth_password=nil)
	url=URI.parse(url_string)
	http = Net::HTTP.new(url.host,url.port)
	req = Net::HTTP::Post.new(url.path)
	if post_data.kind_of?(String) then
		req.body=post_data
	elsif post_data.kind_of?(Hash) then
		req.form_data=post_data
	else
		raise "Invalid post data type."
	end
	if url_string =~ /^https/
		http.use_ssl = true
		http.verify_mode = OpenSSL::SSL::VERIFY_NONE
	end
	req.basic_auth auth_user, auth_password if auth_user and auth_password
	response = http.request(req)
	case response
	when Net::HTTPSuccess
		return response.body
	else
		puts response.body
		response.error!
	end
end

def self.get(url_string, auth_user=nil, auth_password=nil)
	url=URI.parse(url_string)
	http = Net::HTTP.new(url.host,url.port)
	req = Net::HTTP::Get.new(url.path)
	if url_string =~ /^https/
		http.use_ssl = true
		http.verify_mode = OpenSSL::SSL::VERIFY_NONE
	end
	req.basic_auth auth_user, auth_password if auth_user and auth_password
	response = http.request(req)
	case response
	when Net::HTTPSuccess
		return response.body
	else
		response.error!
	end
end

def self.delete(url_string, auth_user=nil, auth_password=nil)
	url=URI.parse(url_string)
	http = Net::HTTP.new(url.host,url.port)
	req = Net::HTTP::Delete.new(url.path)
	if url_string =~ /^https/
		http.use_ssl = true
		http.verify_mode = OpenSSL::SSL::VERIFY_NONE
	end
	req.basic_auth auth_user, auth_password if auth_user and auth_password
	response = http.request(req)
	case response
	when Net::HTTPSuccess
		return response.body
	else
		response.error!
	end
end

end

end
