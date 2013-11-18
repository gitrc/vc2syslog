vc2syslog
=========

vCenter Events to Syslog - VMware provides syslog capabilities in vSphere, just not the vCenter Events which are nicely correlated streams.   I needed a way to collect and transform the vCenter Events into syslog and this code was born.  Certain SIEM vendors will provide this functionality too, presumably through the same event collector polling mechanism.  Here is a free alternative.

https://communities.vmware.com/message/1810318

This code connects to vCenter, pulling events every minute, tracking state by event ID, and then sends spoofed syslog messages to a syslog server.  The purpose of spoofing the packets is to preserve the originating entity (source IP) from which the message originated.  
