# Check-VDI-Percentage-Used

This script will accept a list of Desktop Delivery Controllers and check single session, non-remote pc, and non-test delivery groups for capcity usage.  If greater than 85% is in use, it will generate an email and add it to a csv.  That CSV is then used at the next run to see what has recovered, what is a new usage problem, and what is still a usage problem.
