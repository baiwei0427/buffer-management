import sys
import matplotlib
matplotlib.use('Agg')

import matplotlib.pyplot as plt

if len(sys.argv) != 3:
    print '%s [input log file] [output figure]' % sys.argv[0]
    sys.exit(1)

log_name = sys.argv[1]
fig_name = sys.argv[2]

log_file = open(log_name, 'r')
lines = log_file.readlines()
log_file.close()

port_qlen = []

for line in lines:
    arr = line.split()
    if len(arr) < 2 or float(arr[0]) < 1:
        continue
    port_qlen.append(int(arr[1]) / 1000)

port_qlen.sort()
length = len(port_qlen)
cdf = range(0, length)
length = length + 0.0
cdf[:] = [x * 100 / length for x in cdf]

plt.plot(port_qlen, cdf)
plt.xlabel('Port buffer occupancy (KB)')
plt.ylabel('CDF (%)')
plt.savefig(fig_name)

print '99.9th percentile %d' % port_qlen[int(0.999 * length)]
print '99.99th percentile %d' % port_qlen[int(0.9999 * length)]
