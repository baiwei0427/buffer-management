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
    port_qlen.append(int(arr[1]) / 1024)

port_qlen.sort()
length = len(port_qlen)
cdf = range(0, length)
length = length + 0.0
cdf[:] = [x * 100 / length for x in cdf]

plt.rc('xtick', labelsize = 32)
plt.rc('ytick', labelsize = 32)
plt.rcParams["figure.figsize"] = [16, 9]
plt.rc('grid', linestyle="--", color='black', linewidth = 4)
plt.plot(port_qlen, cdf, linewidth = 10)
plt.xlabel('Port buffer occupancy (KB)\n', fontsize = 40)
plt.ylabel('CDF (%)', fontsize = 40)
plt.gcf().subplots_adjust(bottom=0.15)
plt.grid(True)
plt.savefig(fig_name)

for i in range(1, 100):
    print '%dth percentile %d' % (i, port_qlen[max(int((i + 0.0) * length / 100) - 1, 0)])

print '99.9th percentile %d' % port_qlen[max(int(0.999 * length) - 1, 0)]
print '99.99th percentile %d' % port_qlen[max(int(0.9999 * length) - 1, 0)]
