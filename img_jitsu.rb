require 'rubygems'
require 'uri'
require 'open-uri'
require 'digest/md5'
require 'right_aws'
require 'yaml'
require 'ftools'
require 'RMagick'


class Media
  # @@@@@@@@;)  marge simpson.
  @@s3_config      = YAML.load_file('./config/amazon_s3.yml')
  @@s3_connection  = RightAws::S3.new(@@s3_config['access_key_id'], @@s3_config['secret_access_key'])
  @@sqs_connection = RightAws::Sqs.new(@@s3_config['access_key_id'], @@s3_config['secret_access_key'])
  @@bucket = @@s3_connection.bucket(@@s3_config['bucket'])
  # @@in     = @@sqs_connection.queue(@@s3_config['in_queue'])
  TMP_DIR = './'
  SIZES = {
    :small => '140x140>',
    :medium => '320x320>'
  }
  attr_accessor :url
  
  def self.process_media 
    in_queue  = @@sqs_connection.queue(@@s3_config['in_queue'])
    while in_queue.size > 0
      if i = YAML.load(in_queue.pop.to_s)
        m = Media.new(i[:image][:url], i[:image][:id])
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
  
  def process
    download && resize && sync_to_primary_storage && report
  end
  
protected 
  def download
    begin
      file_extension = @url.split('.').last
      if file_extension.size > 3
        file_extension = ""
      end
      @file_name = Digest::MD5.hexdigest(@url + Time.now.to_s) + ".#{file_extension}"
      open(@url) { |img| File.open(TMP_DIR + @file_name, "wb") { |f| f.puts img.read } }
    rescue Timeout::Error, OpenURI::HTTPError, URI::InvalidURIError
      return false
    end
    true
  end
  
  def resize
    #begin
  
      if @file_name && img = Magick::Image::read(TMP_DIR + @file_name).first
        old_fn = @file_name
        tmp_fn = @file_name.split(".")[0]
        @file_name = tmp_fn + ".#{img.format.gsub('JPEG', 'JPG')}"
        File.mv(TMP_DIR + old_fn, TMP_DIR+ @file_name)
        @mime = img.format
        @height = img.rows
        return false if img.rows < 80
        return false if img.columns < 80
        @width = img.columns
        @size = 31337
        small_fn = @file_name.split('.')[0] + '-small.' + 'jpg'
        medium_fn = @file_name.split('.')[0] + '-medium.' + 'jpg'
        # thumb_s = img.scale(SIZES[:small][:height], SIZES[:small][:width])
        #         thumb_m = img.scale(SIZES[:medium][:height],SIZES[:medium][:width])
        
        thumb_s = img.change_geometry!(SIZES[:small]) { |cols, rows, i|
          i.resize!(cols, rows)
        }
        thumb_s.write TMP_DIR + small_fn
        thumb_m = img.change_geometry!(SIZES[:medium]) { |cols, rows, i|
          i.resize!(cols, rows)
        }
        thumb_m.write TMP_DIR + medium_fn
        @children = [ { :file_name => small_fn, 
                        :size => 31337, 
                        :mime => thumb_s.format, 
                        :height => thumb_s.rows, 
                        :width => thumb_s.columns }, 
                      { :file_name => medium_fn, 
                        :size => 31337, 
                        :mime => thumb_m.format, 
                        :height => thumb_m.rows, 
                        :width => thumb_m.columns } ]
        return true
      end
    #rescue
    #  return false
    #end
    return false
  end
  
  def sync_to_primary_storage
    # sync the original
    open(TMP_DIR + @file_name, "r") do |file|
      key = RightAws::S3::Key.create(@@bucket, @file_name)
      key.put file.read
    end
    File.delete(TMP_DIR + @file_name)
    # sync the children
    @children.each do |child|
      open(TMP_DIR + child[:file_name], "r") do |file|
        key = RightAws::S3::Key.create(@@bucket, child[:file_name])
        key.put file.read
      end
      File.delete(TMP_DIR + child[:file_name])
    end
    true
  end 
  
  def final_check?
    key = RightAws::S3::Key.create(@@bucket, @file_name)
    key.exists? 
  end
  
  def report
    if final_check?
      rpt = {'image' => {'id' => @media_id, 'bucket' => @@s3_config['bucket'], 'original' => {
        'file_name' => @file_name, 'height' => @height, 'width' => @width, 'mime-type' => @mime, 'size' => @size
      } } }
      
      %w(small medium).each_with_index do |size, idx|
        rpt['image'][size] =  {
          'file_name' => @children[idx][:file_name],
          'height' => @children[idx][:height],
          'width' => @children[idx][:width],
          'size' => @children[idx][:size],
          'mime' => @children[idx][:mime]
        }
      end
      @out    = @@sqs_connection.queue(@@s3_config['out_queue'])
      @out.send_message(rpt.to_yaml)
      #puts rpt.to_yaml
      true
    end
  end
end


Media.process_media
