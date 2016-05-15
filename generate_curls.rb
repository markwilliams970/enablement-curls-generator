require 'openssl'
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

require "google_drive"
require "csv"

# Mode variables
$headers_only   = false
$script_mode    = false

# Load (and maybe override with) my personal/private variables from a file...
my_vars= File.dirname(__FILE__) + "/my_vars.rb"
if FileTest.exist?( my_vars ) then require my_vars end

# Encoding
$file_encoding                      = "UTF-8"

# Field delimiter for permissions file
$my_delim                           = ","

# Inputs
$input_file_arg = ARGV[0]
$partner_id     = ARGV[1]

if $input_file_arg == nil || $partner_id == nil then
    puts "Usage: ruby generate_curls.rb featurelist.csv {partnerId}"
    exit
end

# Creates a session. This will prompt the credential via command line for the
# first time and save it to config.json file for later usages.
session = GoogleDrive.saved_session("config.json")

# First worksheet of
# https://docs.google.com/spreadsheet/ccc?key=pz7XtlQC-PYx-jrVMJErTcg
# Or https://docs.google.com/a/someone.com/spreadsheets/d/pz7XtlQC-PYx-jrVMJErTcg/edit?usp=drive_web
ws = session.spreadsheet_by_key($my_spreadsheet_id).worksheets[0]

# Output worksheet attributes
puts "# #{ws.inspect}"

# Column Keys
column_map = {
    "Selected for Enablement" => 0,
    "Feature Number"          => 1,
    "Module"                  => 2,
    "Feature Name"            => 3,
    "Pre-Requisites/Notes"    => 4,
    "Approval Needed"         => 5,
    "Steps to Enable"         => 6,
    "Curl Command"            => 7,
    "Multi-Step"              => 8
}

puts "# Reading input file of features requested..."
# Read input file
$input_filename = $input_file_arg
input  = CSV.read($input_filename, {:col_sep => $my_delim, :encoding => $file_encoding})
header = input.first #ignores first line

rows   = []
feature_list = []
# CSV is 0-indexed, so we're starting at first row.
# Start at row 1. Note - this means, don't add a header row to the input file!!
(0...input.size).each { |i| rows << CSV::Row.new(header, input[i]) }

rows.each do |row|
    feature_name = row[0].downcase.rstrip
    feature_list.push(feature_name)
end

puts "# Reading curls spreadsheet and building list..."
curls_assoc_arr = {}
# Read curls spreadsheet and store each row in hash using feature name as key
# Start at row 2, need to Skip row one - the spreadsheet header row
(2..ws.num_rows).each do |row|
    row_arr = []
      (1..ws.num_cols).each do |col|
        row_arr.push(ws[row, col])
      end
    curl_feature_name = row_arr[column_map["Feature Name"]].downcase

    # A check for manually selected features to enable (i.e. features not in CSV, but checked in the Google doc)
    selected_for_enablement = row_arr[column_map["Selected for Enablement"]]
    if !selected_for_enablement.nil? then
        if selected_for_enablement.length > 0 then
            feature_list.push(curl_feature_name)
        end
    end
    curls_assoc_arr[curl_feature_name] = row_arr
end

puts "# Matching curls on feature names...."
# loop through feature list and output curl for each feature requested
feature_list.each do | this_feature |
    this_curls_arr = curls_assoc_arr[this_feature]

    if !this_curls_arr.nil? then
        feature_number = this_curls_arr[column_map["Feature Number"]]
        feature_name   = this_curls_arr[column_map["Feature Name"]]
        this_module    = this_curls_arr[column_map["Module"]]
        pre_reqs       = this_curls_arr[column_map["Pre-Requisites/Notes"]]
        approval       = this_curls_arr[column_map["Approval Needed"]]
        steps          = this_curls_arr[column_map["Steps to Enable"]]
        curl_cmd       = this_curls_arr[column_map["Curl Command"]]
        multi_step     = this_curls_arr[column_map["Multi-Step"]]
    else
        warning_string = "Warning!! No matching enablement line item found for this Feature."
        header_delim = "#"*warning_string.length
        puts header_delim
        puts this_feature
        puts "Warning!! No matching enablement line item found for this Feature."
        puts header_delim
        puts
    end

    echo_string = "#{feature_number} #{feature_name}"
    header_string = "# #{echo_string}"
    header_delim = "#"*header_string.length

    if !feature_number.nil? then
        puts header_delim
        puts header_string
        puts header_delim

        # Check mode to see if we're outputting only the headers.
        if $headers_only == false then
            if !multi_step.nil? then
                if multi_step.length > 0 then
                    puts "# MULTI-STEP ENABLEMENT!!"
                end
            end
            if !pre_reqs.nil? then
                if pre_reqs.length > 0 then
                    puts "#{pre_reqs}"
                end
            end
            if !approval.nil? then
                if approval.length > 0 then
                    puts "#{approval}"
                end
            end
            if !steps.nil? then
                if steps.length > 0 then
                    puts "#{steps}"
                end
            end
            if !multi_step.nil? && !curl_cmd.nil? && $script_mode == true then
                if multi_step.length == 0 && curl_cmd.length > 0 then
                    echo_header = "#"*(echo_string.length+1)
                    puts "echo \"#{echo_header}\""
                    puts "echo \"#{echo_string}:\""
                    puts "echo \"#{echo_header}\""
                end
            end
            if !curl_cmd.nil? then
                if curl_cmd.length > 0 then
                    puts curl_cmd.gsub("<PartnerID>", $partner_id)
                    if multi_step.length == 0 && $script_mode == true then
                        puts "sleep 10"
                    end
                end
            end
        end
        puts
    end
end

# Reloads the worksheet to get changes by other clients.
# ws.reload