require 'xmpp4r'
require 'xmpp4r/roster/helper/roster'
require 'xmpp4r/vcard/helper/vcard'


def with_status(str, &block)
  print "#{str}..."
  $stdout.flush
  begin
    yield
    puts " Ok"
  rescue Exception => e
    puts " Error: #{e.to_s}"
    raise e
  end
end

class JabberClient
  
  def initialize(account, pwd)
    @account, @pwd = account, pwd
    @connected = false
    @jid = Jabber::JID.new(@account)
    @client = Jabber::Client.new(@jid)
  end
  
  def send(to,msg, subject = 'subject')
    to_jid = Jabber::JID.new(to)
    m = Jabber::Message.new(to_jid, msg).set_type(:normal).set_id('1').set_subject(subject)
    with_status('sending') {@client.send(m)}
  end
  
  # get a vCard
  def get_vcard(item)
    Thread.new do
      begin
        vcard = Jabber::Vcard::Helper.new(@client).get(item.jid)
        unless vcard.nil?
          if vcard['NICKNAME'] # Rename him to vCard's <NICKNAME/> field
            item.iname = vcard['NICKNAME']
            puts("Renaming #{item.jid} to #{vcard['NICKNAME']}")
            item.send
          elsif vcard['FN'] # Rename him to vCard's <FN/> field
            item.iname = vcard['FN']
            puts("Renaming #{item.jid} to #{vcard['FN']}")
            item.send
          else # We've got a lazy one
            puts("#{item.jid} provided no details in vCard")
          end
        end
      rescue Exception => e
        # This will be (mostly) thrown by Jabber::Vcard::Helper#get
        puts("Error getting vCard for #{item.jid}: #{e.to_s}")
      end
    end
  end
  
  def init_roster
    # Callback to handle updated roster items
    @roster.add_update_callback { |olditem,item|
      if [:from, :none].include?(item.subscription) && item.ask != :subscribe
        puts("Subscribing to #{item.jid}")
        item.subscribe
      end
      
      # Print the item
      if olditem.nil?                                                    
        # We didn't knew before:                                       
        puts("#{item.iname} (#{item.jid}, #{item.subscription}) #{item.groups.join(', ')}")
      else                                                             
        # Showing whats different:                                     
        puts("#{olditem.iname} (#{olditem.jid}, #{olditem.subscription}) #{olditem.groups.join(', ')} -> #{item.iname} (#{item.jid}, #{item.subscription}) #{item.groups.join(', ')}")
      end
      
      # If the item has no name associated...
      unless item.iname
        #puts("#{item.jid} has no nickname... getting vCard")
        #get_vcard(item)
      end
    }
    
    # Presence updates:
    @roster.add_presence_callback { |item,oldpres,pres|
      # Can't look for something that just does not exist...
      if pres.nil?
        # ...so create it:
        pres = Jabber::Presence.new
      end
      if oldpres.nil?
        # ...so create it:
        oldpres = Jabber::Presence.new
      end
      
      # Print name and jid:
      name = "#{pres.from}"
      if item.iname
        name = "#{item.iname} (#{pres.from})"
      end
      puts(name)
      
      # Print type changes:
      unless oldpres.type.nil? && pres.type.nil?
        puts("  Type: #{oldpres.type.inspect} -> #{pres.type.inspect}")
      end
      # Print show changes:
      unless oldpres.show.nil? && pres.show.nil?
        puts("  Show:     #{oldpres.show.to_s.inspect} -> #{pres.show.to_s.inspect}")
      end
      # Print status changes:
      unless oldpres.status.nil? && pres.status.nil?
        puts("  Status:   #{oldpres.status.to_s.inspect} -> #{pres.status.to_s.inspect}")
      end
      # Print priority changes:
      unless oldpres.priority.nil? && pres.priority.nil?
        puts("  Priority: #{oldpres.priority.inspect} -> #{pres.priority.inspect}")
      end
      
      # Note: presences with type='error' will reflect our own show/status/priority
      # as it is mostly just a reply from a server. This is *not* a bug.
    }
    
    # Subscription requests and responses:
    subscription_callback = lambda { |item,pres|
      name = pres.from
      if item != nil && item.iname != nil
        name = "#{item.iname} (#{pres.from})"
      end
      case pres.type
        when :subscribe then puts("Subscription request from #{name}")
        when :subscribed then puts("Subscribed to #{name}")
        when :unsubscribe then puts("Unsubscription request from #{name}")
        when :unsubscribed then puts("Unsubscribed from #{name}")
      else raise "The Roster Helper is buggy!!! subscription callback with type=#{pres.type}"
      end
    }
    @roster.add_subscription_callback(0, nil, &subscription_callback)
    @roster.add_subscription_request_callback(0, nil, &subscription_callback)
    
  end
  
  # Main loop
  def main
    begin
      # log in
      with_status('connecting') {@client.connect}
      with_status('auth') {@client.auth(@pwd)}
      @connected = true
      
      @roster = Jabber::Roster::Helper.new(@client)
      init_roster
      # msg callback
      @client.add_message_callback do |m|
        if m.type != :error
          puts "#{m.from}: #{m.body}"
        else
          puts "Error: #{m.to_s}"
        end
      end
      
      # Presence
      @client.send(Jabber::Presence.new.set_show(:xa).set_status('Testing XMPP with Ruby...'))
      
      # list roster groups
      @roster.groups.each { |group|
        if group.nil?
          puts "*** Ungrouped ***"
        else
          puts "*** #{group} ***"
        end
        @roster.find_by_group(group).each { |item|
          puts "- #{item.iname} (#{item.jid})"
        }
        print "\n"
      }
      
      # send test msg
      @roster.add('faivrem@gmail.com', 'Mickael', true)
      send('faivrem@gmail.com','I am here !')
      # loop
      loop { sleep(1); }
    rescue Jabber::AuthenticationFailure => t
      puts "Auth Failure: #{t}"
    rescue Exception => t
      puts "Except: #{t}"
    end
    with_status('closing') {@client.close}
  end
  
end

print "account (name@gmail.com): "
login = gets.chomp
print "password: "
pwd   = gets.chomp
cl = JabberClient.new(login,pwd)
cl.main
puts 'end'
