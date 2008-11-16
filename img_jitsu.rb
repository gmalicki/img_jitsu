require 'rubygems'
require 'uri'
require 'open-uri'
require 'digest/md5'
require 'right_aws'
require 'yaml'
require 'ftools'
gem 'rmagick'


class Media
  # @@@@@@@@;)  marge simpson.
  @@s3_config      = YAML.load_file('./config/amazon_s3.yml')
  @@s3_connection  = RightAws::S3.new(@@s3_config['access_key_id'], @@s3_config['secret_access_key'])
  @@sqs_connection = RightAws::Sqs.new(@@s3_config['access_key_id'], @@s3_config['secret_access_key'])
  @@bucket = @@s3_config['bucket']
  # @@in     = @@sqs_connection.queue(@@s3_config['in_queue'])
  TMP_DIR = './'
  SIZES = {
    :small => {:width => 10, :height => 10},
    :medium => {:width => 50, :height => 50}
  }
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
    @height = 0
    @width = 0
    @mime = ''
    @size = 0
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
    #begin
    puts "got to resize"
      if @filename && img = Image.new(TMP_DIR + @file_name)
        puts "created image"
        # set the mime type for the original record
        @mime = img.format
        file_extension = @url.split('.').last
        small_fn = @file_name.split('.')[0] + '-small.' + file_extension
        medium_fn = @file_name.split('.')[0] + '-medium.' + file_extension
        thumb_s = img.scale(SIZES[:small][:height], SIZES[:small][:width])
        thumb_m = img.scale(SIZES[:medium][:height],SIZES[:medium][:width])
        thumb_s.write TMP_DIR + small_fn
        thumb_m.write TMP_DIR + medium_fn
        @children = [ { :file_name => small_fn, 
                        :size => thumb_s.size, 
                        :mime => thumb_s.format, 
                        :height => thumb_s.rows, 
                        :width => thumb_s.columns }, 
                      { :file_name => medium_fn, 
                        :size => thumb_m.size, 
                        :mime => thumb_m.format, 
                        :height => thumb_m.rows, 
                        :width => thumb_m.columns } ]
      end
    #rescue
    #  return false
    #end
    true
  end
  
  def sync_to_primary_storage
    bucket = @@s3_connection.bucket(@@bucket)
    # sync the original
    open(TMP_DIR + @file_name, "r") do |file|
      key = RightAws::S3::Key.create(bucket, @file_name)
      key.put file.read
    end
    File.delete(TMP_DIR + @file_name)
    # sync the children
    @children.each do |child|
      open(TMP_DIR + child[:file_name], "r") do |file|
        key = RightAws::S3::Key.create(bucket, child[:file_name])
        key.put file.read
      end
      File.delete(TMP_DIR + child[:file_name])
    end
    true
  end 
  
  def final_check?
    # fetch the original, and children from their s3 buckets. Compare file sizes. 
    true
  end
  
  def report
    if final_check?
      rpt = {'image' => {'id' => @media_id, 'bucket' => @@bucket, 'original' => {
        'file_name' => @file_name, 'height' => @height, 'width' => @width, 'mime-type' => @mime, 'size' => @size
      } } }
      
      %w(small medium).each_with_index do |size, idx|
        rpt[size] =  {
          'file_name' => @children[idx][:file_name],
          'height' => @children[idx][:height],
          'width' => @children[idx][:width],
          'size' => @children[idx][:size],
          'mime' => @children[idx][:mime]
        }
      end
      @out    = @@sqs_connection.queue(@@s3_config['out_queue'])
      @out.send_messsage(rpt.to_yml)
      true
    end
  end
end