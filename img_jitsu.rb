require 'uri'
require 'open-uri'
require 'digest/md5'
require 'right_aws'
require 'yaml'
require 'ftools'

class Media
  # @@@@@@@@;)  marge simpson.
  @@s3_config      = YAML.load_file('./config/amazon_s3.yml')
  @@s3_connection  = RightAws::S3.new(@@s3_config['access_key_id'], @@s3_config['secret_access_key'])
  @@sqs_connection = RightAws::Sqs.new(@@s3_config['access_key_id'], @@s3_config['secret_access_key'])
  @@bucket = @@s3_config['bucket']
  # @@in     = @@sqs_connection.queue(@@s3_config['in_queue'])
  TMP_DIR = './'
  attr_accessor :url
  
  def self.process_media 
    in_queue  = @@sqs_connection.queue(@@s3_config['in_queue'])
    while in_queue.size > 0
      if i = YAML.load(in_queue.pop.to_s)
        m = Media.new(i['url'], i['id'])
        m.process
      end
    end
  end
  
  def initialize(url, media_id)
    @url      = url
    @media_id = media_id
    @children = []
  end
  
protected 
  def process
    download && resize && sync_to_primary_storage && report
  end
  
  def download
    begin
      file_extension = @url.split('.').last
      @file_name = Digest::MD5.hexdigest(@url + Time.now.to_s) + ".#{file_extension}"
      open(@url) { |img| File.open(TMP_DIR + @file_name, "wb") { |f| f.puts img.read } }
    rescue
      return false
    end
    true
  end
  
  def resize
    if @file_name
      file_extension = @url.split('.').last
      small = @file_name.split('.')[0] + '-small.' + file_extension
      medium = @file_name.split('.')[0] + '-medium.' + file_extension
      File.copy(TMP_DIR + @file_name, TMP_DIR + small)
      File.copy(TMP_DIR + @file_name, TMP_DIR + medium)
      @children = [{:file_name => small, :size => 0}, {:file_name => small, :size => 0}]
      true
    end
  end
  
  def sync_to_primary_storage
    # sync the original
    open(TMP_DIR + @file_name, "r") do |file|
      key = RightAws::S3::Key.create(@@bucket, @file_name)
      key.put f.read
    end
    File.delete(TMP_DIR + @file_name)
    # sync the children
    @children.each do |child|
      open(TMP_DIR + child[:file_name], "r") do |file|
        key = RightAws::S3::Key.create(@@bucket, child[:file_name])
        key.put f.read
      end
      File.delete(TMP_DIR + child[:file_name])
    end
    true
  end 
  
  def final_check
    # fetch the original, and children from their s3 buckets. Compare file sizes. 
    true
  end
  
  def report
    if final_check?
      rpt = {}
      @out    = @@sqs_connection.queue(@@s3_config['out_queue'])
      @out.send_messsage(rpt.to_yml)
    end
  end
end