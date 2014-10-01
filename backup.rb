# Adapted from http://blog.vicecity.co.uk/post/4425574978/multipart-uploads-fog-threads-win
require 'rubygems'
require 'fileutils'
require 'fog'
require 'digest/md5'
require 'base64'
include FileUtils

def send_to_amazon(object_to_upload)
  # Setup connection
  stor = Fog::Storage.new(
    :provider => 'AWS',
    :aws_access_key_id => ENV['S3_ACCESS_KEY_ID'],
    :aws_secret_access_key => ENV['S3_SECRET_ACCESS_KEY'],
    :region => 'us-east-1'
  )

  # Don't want to get caught out with any time errors
  stor.sync_clock

  # Take a test file and split it up, remove the initial / to use the filename and path as the key
  #object_to_upload = "#{pwd}/tmp/10g.img"
  #object_key = object_to_upload[1..-1]
  object_key =  File.basename(object_to_upload)
  
  # Area to place the split file into
  workdir = "/tmp/tmp_db/#{File.basename(object_to_upload)}/"
  FileUtils.mkdir_p(workdir)

  # Split the file into chunks, the chunks are 000, 001, etc
  #`split -C 10M -a 3 -d #{object_to_upload} #{workdir}`
  `split -C 100M -a 3 -d #{object_to_upload} #{workdir}`

  begin
    # Map of the file_part => md5
    parts = {}

    # Get the Base64 encoded MD5 of each file
    Dir.entries(workdir).each do |file|
      next if file =~ /\.\./
      next if file =~ /\./

      md5 = Base64.encode64(Digest::MD5.file("#{workdir}/#{file}").digest).chomp!

      full_path = "#{workdir}#{file}"

      parts[full_path] = md5
    end

    ### Now ready to perform the actual upload

    # Initiate the upload and get the uploadid
    multi_part_up = stor.initiate_multipart_upload(ENV['S3_BUCKET'], object_key, { 'x-amz-acl' => 'private' } )
    upload_id = multi_part_up.body["UploadId"]

    # Lists for the threads and tags
    tags = []
    threads = []

    sorted_parts = parts.sort_by do |d|
      d[0].split('/').last.to_i
    end

    sorted_parts.each_with_index do |entry, idx|
      # Part numbers need to start at 1
      part_number = idx + 1

      # Reload to stop the connection timing out, useful when uploading large chunks
      stor.reload

      # Create a new thread for each part we are wanting to upload.
      threads << Thread.new(entry) do |e|
        print "DEBUG: Starting on File: #{e[0]} with MD5: #{e[1]} - this is part #{part_number} \n"

        # Pass fog a file object to upload
        File.open(e[0]) do |file_part|

          # The part_number changes each time, as does the file_part, however as they are set outside of the threads being created I *think* they are
          # safe. Really need to dig into the pickaxe threading section some more..
          part_upload = stor.upload_part(ENV['S3_BUCKET'], object_key, upload_id, part_number, file_part, { 'Content-MD5' => e[1] } )

          # You need to make sure the tags array has the tags in the correct order, else the upload won't complete
          tags[idx] = part_upload.headers["ETag"]

          print "#{part_upload.inspect} \n" # This will return when the part has uploaded
        end
      end
    end

    # Make sure all of our threads have finished before we continue
    threads.each do |t|
      begin
        t.join
      rescue Exception => e
        puts "Failed: #{e.message}"
      end
    end

    stor.reload
    completed_upload = stor.complete_multipart_upload(ENV['S3_BUCKET'], object_key, upload_id, tags)

  ensure
    rm_rf(workdir)
  end
end

def verify_configuration!
  fail "No S3_ACCESS_KEY_ID set in the current environment" unless ENV['S3_ACCESS_KEY_ID']
  fail "No S3_SECRET_ACCESS_KEY set in the current environment" unless ENV['S3_SECRET_ACCESS_KEY']
  fail "No S3_BUCKET set in the current environment" unless ENV['S3_BUCKET']
  fail "No PG_DBNAME set in the current environment" unless ENV['PG_DBNAME']
end

def run
  verify_configuration!
  datestamp = Time.now.strftime("%Y-%m-%d_%H-%M-%S")
  backup_file = "#{pwd}/tmp/ahalogy_prod_#{datestamp}_dump.bak"

  puts "Starting production backup.."
  Kernel::system "pg_dump --no-privileges --file=#{backup_file} -Fc #{ENV['PG_DBNAME']}"

  puts "Uploading production backup to S3"
  begin
    send_to_amazon backup_file
  rescue Exception => e
    puts "Production upload failed: #{e.message}"
  ensure
    File.delete backup_file
  end

  puts "Done."
end

run
