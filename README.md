# S26 Wrap-Up

We have a packaged PCS IP under `FPGA/PCS_IP`. 

To add it to an existing Vivado project, just run this from the Tcl console it pulls the IP straight from GitHub, so you don't need a local clone:

```tcl
source {path to}/add_pcs_ip.tcl
```

![alt text](media/PCS_IP.png)

A standalone synthesis/timing project is also provided. The script creates a full Vivado project targeting the ZCU106 with an LFSR wrapper (the IP can't be set as top by itself as its number of IOs exceeds the count on FPGA). Also pulls everything from GitHub automatically:

```tcl
source {path to}/build_pcs_tmp_wrapper.tcl
```

Both scripts only need `git` on PATH and a Vivado window open.

Disclaimer: future updates possible based on precise SerDes configuration and any architectural complexity/need that later arise.

Up-to-date revised documentation can be found on the Notion page.