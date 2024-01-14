require "crest"
require "json"

def time_ago_in_words(from_time, to_time)
  difference = to_time - from_time
  minutes = (difference / 60).to_i
  hours = (minutes / 60).to_i
  days = (hours / 24).to_i
  weeks = (days / 7).to_i
  months = (days / 30).to_i

  case minutes
  when 0..1
    "one minute"
  when 2..59
    "#{minutes} minutes"
  when 60..119
    "an hour"
  when 120..1439
    "#{hours} hours"
  when 1440..10079
    "#{days} days"
  when 10080..43199
    "#{weeks} weeks"
  else
    "more than a month <%--(#{minutes}/#{hours}/#{days}/#{weeks}/#{months})-->"
  end
end

print "Collecting time from primary mirrors..."
atl_resp = Crest.get "https://atl.rsync.repo.almalinux.org/almalinux/TIME"
sea_resp = Crest.get "https://sea.rsync.repo.almalinux.org/almalinux/TIME"

if atl_resp.body.to_i >= sea_resp.body.to_i
  puts " done. Using time from ATL"
  original_time = Time.unix atl_resp.body.to_i
else
  puts " done. Using time from SEA"
  original_time = Time.unix sea_resp.body.to_i
end

print "Collecting mirror list..."
all_mirrors = Crest.get "https://mirrors.almalinux.org/debug/json/all_mirrors"
mirrorlist = JSON.parse(all_mirrors.body)["result"]
puts " done."

md = String::Builder.new
in_sync = String::Builder.new
behind = String::Builder.new
unavailable = String::Builder.new

md << "---\n"
md << "hide:\n"
md << "  - footer\n"
md << "  - toc\n"
md << "  - navigation\n"
md << "---\n"
md << "\n"
md << "# AlmaLinux Mirror Propagation Report\n"
md << "\n"
md << "This service provides information about the status of the AlmaLinux mirrors. The report shows the time it takes for updates to propagate to the mirrors, as well as the number of mirrors that have been updated. This information can be used to identify mirrors that are not up to date, and to troubleshoot any problems with the mirror propagation process.\n"
md << "\n"
md << "- Source mirror address: `rsync.repo.almalinux.org`\n"
md << "- Source mirror build date: `#{original_time}`\n"
md << "\n"

mirrorlist_total = mirrorlist.as_h.each_key.size
mirrorlist_completed = 0

puts "Starting mirror probe..."

mirrorlist.as_h.each_key do |mirror| 
  if mirrorlist[mirror]["status"] == "ok" && mirrorlist[mirror]["private"] == false 
    sponsor = mirrorlist[mirror]["sponsor_name"]
    sponsor_url = mirrorlist[mirror]["sponsor_url"]

    if mirrorlist[mirror]["urls"].as_h.has_key? "http"
      mirror_address = mirrorlist[mirror]["urls"]["http"]
    else
      mirror_address = mirrorlist[mirror]["urls"]["https"]
    end

    unless mirror_address.to_s.ends_with? "/"
      mirror_address = "#{mirror_address}/"
    end

    begin
      mirror_resp = Crest.get "#{mirror_address}TIME", read_timeout: 2.seconds, connect_timeout: 2.seconds, max_redirects: 2

      if mirror_resp.success?
        mirror_time = Time.unix mirror_resp.body.to_i
        compare = original_time <=> mirror_time

        if compare <= 0
          in_sync << "    | #{mirror} | [#{sponsor}](#{sponsor_url}) |\n"
        else
          behind << "    | #{mirror} | [#{sponsor}](#{sponsor_url}) | #{time_ago_in_words mirror_time, original_time} |\n"
        end
      else
        unavailable << "    | #{mirror} | [#{sponsor}](#{sponsor_url}) | #{mirror_resp.status_code}\n"
      end
    rescue exception
      unavailable << "    | #{mirror} | [#{sponsor}](#{sponsor_url}) | #{exception} |\n"
    end
  end
  mirrorlist_completed = mirrorlist_completed + 1

  puts "  #{((mirrorlist_completed / mirrorlist_total) * 100).ceil}%"
end

md << "=== \"In sync\"\n"
md << "\n"
md << "    | Mirror Name | Sponsor |\n"
md << "    |:--|:--|\n"
md << in_sync.to_s

md << "\n"
md << "=== \"Behind primary\"\n"
md << "\n"
md << "    | Mirror Name | Sponsor | Time behind primary |\n"
md << "    |:--|:--|:--|\n"
md << behind.to_s

md << "\n"
md << "=== \"Unavailable\"\n"
md << "\n"
md << "    | Mirror Name | Sponsor | Reason |\n"
md << "    |:--|:--|:--|\n"
md << unavailable.to_s

md << "\n"
md << "\n"
md << "Last report update: `#{Time.utc}`"
md << ""

print "Writing Markdown..."
File.write("docs/index.md", md.to_s)
puts " done."
