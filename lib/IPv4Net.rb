module NetAddr
	
	#IPv4Net represents an IPv4 network. 
	class IPv4Net
		
		#arguments:
		#* ip - an IPv4 object
		#* m32 - a Mask32 object. will default to a /32 if nil
		def initialize(ip,m32)
			if (!ip.kind_of?(IPv4))
				raise ArgumentError, "Expected an IPv4 object for 'ip' but got a #{ip.class}."
			elsif (m32 != nil && !m32.kind_of?(Mask32))
				raise ArgumentError, "Expected a Mask32 object for 'm32' but got a #{m32.class}."
			end
			
			if (m32 == nil)
				m32 = Mask32.new(32)
			end
			@m32 = m32
			@base = IPv4.new(ip.addr & m32.mask)
		end
		
		# parse will create an IPv4Net from its string representation. Will default to a /32 netmask if not specified.
		# Throws ValidationError on error.
		def IPv4Net.parse(net)
			net.strip!
			if (net.include?("/")) # cidr format
				addr,mask = net.split("/")
			elsif (net.include?(" ") ) # extended format
				addr,mask = net.split(' ')
			else
				addr = net
				mask = "32"
			end
			ip = IPv4.parse(addr)
			m32 = Mask32.parse(mask)
			return IPv4Net.new(ip,m32)
		end

		# extended returns the IPv4Net in extended format (eg. x.x.x.x y.y.y.y)
		def extended()
			return @base.to_s + " " + NetAddr.int_to_IPv4(@m32.mask)
		end
		
		#cmp compares equality with another IPv4Net. Return:
		#* 1 if this IPv4Net is numerically greater
		#* 0 if the two are equal
		#* -1 if this IPv4Net is numerically less
		#
		#The comparasin is initially performed on using the cmp() method of the network address, however, in cases where the network #addresses are identical then the netmasks will be compared with the cmp() method of the netmask. 
		def cmp(other)
			if (!other.kind_of?(IPv4Net))
				raise ArgumentError, "Expected an IPv4Net object for 'other' but got a #{other.class}."
			end
			cmp = self.network.cmp(other.network)
			if (cmp != 0)
				return cmp
			end
			return self.netmask.cmp(other.netmask)
		end
		
		# fill returns a copy of the given Array, stripped of any networks which are not subnets of this IPv4Net
		# and with any missing gaps filled in.
		def fill(list)
			list = NetAddr.filter_IPv4Net(list)
			
			# sort & git rid of non subnets
			subs = []
			NetAddr.discard_subnets(list).each do |sub|
				r = self.rel(sub)
				if (r == 1)
					subs.push(sub)
				end
			end
			subs = NetAddr.quick_sort(subs)
			
			filled = []
			if (subs.length > 0)
				# bottom fill if base missing
				base = self.network.addr
				if (subs[0].network.addr != base)
					filled = subs[0].backfill(base)
				end
				
				# fill gaps
				sib = self.nth_sib(1,false)
				ceil = 0xffffffff
				if (sib != nil)
					ceil = sib.network.addr
				end
				
				0.upto(subs.length-1) do |i|
					sub = subs[i]
					filled.push(sub)
					limit = ceil
					if (i+1 < subs.length)
						limit = subs[i+1].network.addr
					end
					filled.concat( sub.fwdfill(limit) )
				end
			end
			return filled
		end
		
		# netmask returns the Mask32 object representing the netmask for this network
		def netmask()
			@m32
		end
			
		# network returns the IPv4 object representing the network address
		def network()
			@base
		end
		
		#len returns the number of IP addresses in this network. It will always return 0 for /0 networks.
		def len()
			return self.netmask.len
		end
		
		# next returns the next largest consecutive IP network or nil if the end of the address space is reached.
		def next()
			net = self.nth_sib(1,false)
			if (!net)
				return nil
			end
			return net.grow
		end
		
		# next_sib returns the network immediately following this one or nil if the end of the address space is reached.
		def next_sib()
			self.nth_sib(1,false)
		end
		
		# nth returns the IPv4 at the given index.
		# The size of the network may be determined with the len() method.
		# If the range is exceeded then return nil.
		def nth(index)
			if (!index.kind_of?(Integer))
				raise ArgumentError, "Expected an Integer for 'index' but got a #{index.class}."
			elsif (index >= self.len)
				return nil
			end
			return IPv4.new(self.network.addr + index)
		end
		
		# nth_subnet returns the subnet IPv4Net at the given index.
		# The number of subnets may be determined with the subnet_count() method.
		# If the range is exceeded  or an invalid prefix_len is provided then return nil.
		def nth_subnet(prefix_len,index)
			count = self.subnet_count(prefix_len)
			if (count == 0 || index >= count)
				return nil
			end
			sub0 = IPv4Net.new(self.network, Mask32.new(prefix_len))
			return sub0.nth_sib(index,false)
		end
		
		# prev returns the previous largest consecutive IP network or nil if this is 0.0.0.0.
		def prev()
			net = self.grow
			return net.nth_sib(1,true)
		end
		
		# prev_sib returns the network immediately preceding this one or nil if this network is 0.0.0.0.
		def prev_sib()
			self.nth_sib(1,true)
		end
		
		# rel determines the relationship to another IPv4Net. Retuns:
		# * 1 if this IPv4Net is the supernet of other
		# * 0 if the two are equal
		# * -1 if this IPv4Net is a subnet of other
		# * nil if the networks are unrelated
		def rel(other)
			if (!other.kind_of?(IPv4Net))
				raise ArgumentError, "Expected an IPv4Net object for 'other' but got a #{other.class}."
			end
			
			# when networks are equal then we can look exlusively at the netmask
			if (self.network.addr == other.network.addr)
				return self.netmask.cmp(other.netmask)
			end
			
			# when networks are not equal we can use hostmask to test if they are
			# related and which is the supernet vs the subnet
			hostmask = self.netmask.mask ^ 0xffffffff
			otherHostmask = other.netmask.mask ^ 0xffffffff
			if (self.network.addr|hostmask == other.network.addr|hostmask)
				return 1
			elsif (self.network.addr|otherHostmask == other.network.addr|otherHostmask)
				return -1
			end
			return nil
		end
		
		# resize returns a copy of the network with an adjusted netmask.
		# Throws ValidationError on invalid prefix_len.
		def resize(prefix_len)
			m32 = Mask32.new(prefix_len)
			return IPv4Net.new(self.network,m32)
		end
		
		# subnet_count returns the number a subnets of a given prefix length that this IPv4Net contains.
		# It will return 0 for invalid requests (ie. bad prefix or prefix is shorter than that of this network).
		# It will also return 0 if the result exceeds the capacity of a 32-bit integer (ie. if you want the # of /32 a /0 will hold)
		def subnet_count(prefix_len)
			if (prefix_len <= self.netmask.prefix_len || prefix_len > 32 || prefix_len - self.netmask.prefix_len >= 32)
				return 0
			end
			return 1 << (prefix_len - self.netmask.prefix_len)
		end
		
		# summ creates a summary address from this IPv4Net and another.
		# It returns nil if the two networks are incapable of being summarized.
		def summ(other)
			if (!other.kind_of?(IPv4Net))
				raise ArgumentError, "Expected an IPv4Net object for 'other' but got a #{other.class}."
			end
			
			# netmasks must be identical
			if (self.netmask.prefix_len != other.netmask.prefix_len)
				return nil
			end
			
			# merge-able networks will be identical if you right shift them by the number of bits in the hostmask + 1
			shift = 32 - self.netmask.prefix_len + 1
			addr = self.network.addr >> shift
			otherAddr = other.network.addr >> shift
			if (addr != otherAddr)
				return nil
			end
			return self.resize(self.netmask.prefix_len - 1)
		end
		
		# to_s returns the IPv4Net as a String
		def to_s()
			return @base.to_s + @m32.to_s
		end
		
		
		protected
		
		# backfill generates subnets between this net and the limit address.
		# limit should be < net. will create subnets up to and including limit.
		def backfill(limit)
			nets = []
			cur = self
			while true do
				net = cur.prev
				if (net == nil || net.network.addr < limit)
					break
				end
				nets.unshift(net)
				cur = net
			end
			return nets
		end
		
		# fwdfill returns subnets between this net and the limit address.
		# limit should be > net. will create subnets up to limit.
		def fwdfill(limit)
			nets = []
			cur = self
			while true do
				net = cur.next
				if (net == nil || net.network.addr >= limit)
					break
				end
				nets.push(net)
				cur = net
			end
			return nets
		end
		
		# grow decreases the prefix length as much as possible without crossing a bit boundary.
		def grow()
			addr = self.network.addr
			mask = self.netmask.mask
			prefix_len = self.netmask.prefix_len
			self.netmask.prefix_len.downto(0) do
				mask = (mask << 1) & 0xffffffff
				if addr|mask != mask || prefix_len == 0 # // bit boundary crossed when there are '1' bits in the host portion
					break
				end
				prefix_len -= 1
			end
			return IPv4Net.new(IPv4.new(addr),Mask32.new(prefix_len))
		end

		# nth_sib returns the nth next sibling network or nil if address space exceeded.
		# nth_sib will return the nth previous sibling if prev is true
		def nth_sib(nth,prev)
			if (nth < 0)
				return nil
			end
			
			addr = 0
			# right shift by # of bits of host portion of address, add nth.
			# and left shift back. this is the sibling network.
			shift = 32 - self.netmask.prefix_len
			if (prev)
				addr = ((self.network.addr>>shift) - nth) << shift
				if addr < 0
					return nil
				end
			else
				addr = ((self.network.addr>>shift) + nth) << shift
				if addr > 0xffffffff
					return nil
				end
			end
			return IPv4Net.new(IPv4.new(addr), self.netmask)
		end
		
	end # end class IPv4Net
	
end # end module
