# add_pcs_ip.tcl
# Fetches the PCS IP from GitHub and adds it to your current Vivado project.
# No local clone needed; just source this script with a project open. (provide appropriate path to the script).

# from vivado tcl console:
# source {path}/add_pcs_ip.tcl

# or paste the contents directly into the tcl console.

set repo_url "https://github.com/UW-ASIC/10G-Ethernet-Parser.git"
set branch   "PCS"
set ip_dir   [file normalize "[get_property DIRECTORY [current_project]]/ip_repo/PCS_IP"]

if {![file exists ${ip_dir}/component.xml]} {
    puts "Fetching PCS IP from ${repo_url} (branch: ${branch})..."
    file mkdir ${ip_dir}
    set tmp "${ip_dir}/_tmp"

file delete -force ${tmp}
exec git clone --depth 1 --branch ${branch} --filter=blob:none --sparse ${repo_url} ${tmp} 2>@1
    exec -ignorestderr git -C ${tmp} sparse-checkout set FPGA/PCS_IP
    foreach f [glob ${tmp}/FPGA/PCS_IP/*] {
        file copy -force ${f} ${ip_dir}
    }
    file delete -force ${tmp}
    puts "Fetched to: ${ip_dir}"
} else {
    puts "PCS IP already present at: ${ip_dir}"
}

set current_repos [get_property ip_repo_paths [current_project]]
if {[lsearch -exact ${current_repos} ${ip_dir}] == -1} {
    lappend current_repos ${ip_dir}
    set_property ip_repo_paths ${current_repos} [current_project]
}
update_ip_catalog

puts "-------------------------------------"
puts "  PCS IP ready: ${ip_dir}"
puts "  IP Catalog -> search 'IP_10GBASE_R'"
puts "-------------------------------------"