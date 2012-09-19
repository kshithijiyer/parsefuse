#!/usr/bin/env ruby

require 'parsefuse'

class FuseMsg

  module Go
    extend self

    def makehead out
      out <<
<<GOBLOCK
package parsefuse

import (
	"log"
	"unsafe"
)

func clen(n []byte) int {
	for i := 0; i < len(n); i++ {
		if n[i] == 0 {
			return i
		}
	}
	log.Fatal("terminating zero not found in C string")
	return -1
}
GOBLOCK
    end

    def opcodemap cn
      cn.sub(/^FUSE_/, "")
    end

    def makeopcodes out
      out << "const(\n"
      Ctypes[:Enum].each { |e,a|
        a.each { |n,v|
          v or next
          out << "\t#{opcodemap n} uint32 = #{v}\n"
        }
      }
      out << ")\n\n"

      out << "var FuseOpnames = [...]string{\n"
      used = Set.new [nil]
      Ctypes[:Enum].each { |e,a|
        a.each { |n,v|
          used.include? v and next
          n = opcodemap n
          out << %Q(\t#{n}: "#{n}",\n)
          used << v
        }
      }
      out << "}\n\n"
    end

    def camelize nam
      nam.split("_").map { |x| x.capitalize }.join
    end

    def typemap tnam
      case tnam
      when /^fuse_(.*)|(^cuse.*)/
        camelize($1||$2)
      when /^__u(\d+)$/
        "uint#{$1}"
      when /^__s(\d+)$/
        "int#{$1}"
      when "char"
        "*byte"
      when "string"
        "string"
      else
        raise "unknown C type #{tnam}"
      end
    end

    def makestruct name, desc, out
      out << "type #{typemap name} struct {\n"
      desc.each { |f,v|
        out << "\t#{camelize v} #{typemap f}\n"
      }
      out << "}\n\n"
    end

    def makestructs out
      Ctypes[:Struct].each { |s,d|
        makestruct s, d, out
      }
    end

    def makehandler fnam, mmap, out
      out <<
<<GOBLOCK
func #{fnam}(opcode uint32, data []byte) (a []interface{}) {
	pos := 0
	a = make([]interface{}, 0, 2)
	switch opcode {
GOBLOCK
      mmap.each do |c,d|
        d or next
        d = d.map { |t| typemap t }
        d[0...-1].include? "*byte" and raise "*byte type must be trailing"
        out <<
<<GOBLOCK
        case #{opcodemap c}:
GOBLOCK
        strings = 0
        d.each_with_index do |t,i|
          out << case t
          when "*byte"
<<GOBLOCK
		a = append(a, data[pos:])
GOBLOCK
          when "string"
<<GOBLOCK
		l #{(strings += 1) == 1 ? ":" : ""}= clen(data[pos:])
		a = append(a, string(data[pos:][:l]))
		pos += l + 1
GOBLOCK
          else
<<GOBLOCK
		var q#{i} *#{t}
		if len(data[pos:]) >= int(unsafe.Sizeof(*q#{i})) {
			q#{i} := (*#{t})(unsafe.Pointer(&data[pos]))
			a = append(a, *q#{i})
			pos += int(unsafe.Sizeof(*q#{i}))
		} else {
				a = append(a, data[pos:])
		}
GOBLOCK
          end
        end
      end
      out <<
<<GOBLOCK
	default:
		if FuseOpnames[opcode] == "" {
			log.Printf("warning: unknown opcode %d", opcode)
		} else {
			log.Printf("warning: format spec missing for %s", FuseOpnames[opcode])
		}
		a = append(a, data)
	}
	return
}

GOBLOCK
    end

    def makehandlers out
      Msgmap.each { |c, m|
         makehandler "Handle#{c}", m, out
      }
    end

    def makeall out
      makehead out
      makeopcodes out
      makestructs out
      makehandlers out
    end

  end
end

if __FILE__ == $0
  require 'optparse'

  protoh = nil
  msgy = nil
  OptionParser.new do |op|
    op.on('-p', '--proto_head F') { |v| protoh = v }
    op.on('-m', '--msgdef F') { |v| msgy = v }
  end.parse!
  FuseMsg.import_proto protoh, msgy
  FuseMsg::Go.makeall $>
end
