local DEBUG = true;

enum STATE {
    nobody = "nobody",
    pee = "pee",
    poop = "poop",
    error = "error"
}
class detector {
    static MIN_RANGE = 3.0;
    static MAX_RANGE_POO = 8.0;
    static MAX_RANGE_PEE = 89.0;
    static MAX_RANGE = 100.0;
    static COUNT_THRESH = 4; // number of samples that must fall in a range bin
    
    pee_count = 0;
    poo_count = 0;
    state = STATE.nobody;
    
    constructor(){
        pee_count = 0;
        poo_count = 0;
        state = STATE.nobody;
    }

    // updates the state and returns it to the caller
    function detect_person(range_in) {
        if ((range_in < MIN_RANGE) || (range_in > MAX_RANGE)) {
            // range is invalid
            if (DEBUG) server.log("error: unexpected range value: " + range_in);
            state = STATE.error;
            pee_count = 0;
            poo_count = 0;
        }
        else if (range_in < MAX_RANGE_POO) {
            // range is valid and within poop range
            poo_count++;
            if (poo_count > COUNT_THRESH) {
                state = STATE.poop;
                poo_count = COUNT_THRESH;
                pee_count = 0;
            }
        }
        else if (range_in < MAX_RANGE_PEE) {
            // range is valid and in pee range
            pee_count++;
            if (pee_count > COUNT_THRESH) {
                state = STATE.pee;
                pee_count = COUNT_THRESH;
                poo_count = 0;
            }
        }
        else {
            poo_count--;
            pee_count--;
            if ((poo_count < 0) || (pee_count < 0)) {
                poo_count = 0;
                pee_count = 0;
                state = STATE.nobody;
            }
        }
        return state;
    }
};

class batt_monitor {
    static I2C_ADDR = 0x6C;
    // register definitions:
    static REG_VCELL = "\x02";
    static REG_SOC = "\x04";
    static REG_MODE = "\x06";
    static REG_VERSION = "\x08";
    static REG_CONFIG = "\x0C";
    static REG_COMMAND = "\xFE";

    i2c_ = null;

    constructor(i2c_instance) {
        i2c_ = i2c_instance;
        this.reset();
        this.write_config();
    }
    
    function reset() {
        if (DEBUG) server.log("reset SoC monitor");
        i2c_.write(I2C_ADDR, REG_COMMAND + "\x54\x00");
    }

    /*
    sets the config register of the soc monitor
    */
    function write_config() {
        const DFT_RCOMP = "\x97"; // factory recommended compensation values
        const DFT_ALERT = "\x00"; // disable alert functionality and set threshold to 0%
        if (DEBUG) server.log("configured SOC monitor");
        i2c_.write(I2C_ADDR, REG_CONFIG + DFT_RCOMP + DFT_ALERT);
    }

    /*
    returns cell state of charge in percent
    */
    function charge_percent() {
        local soc = i2c_.read(I2C_ADDR, REG_SOC, 2);
        if (soc == null) {
            server.log("error: could not read SoC charge percentage");
            return;
        }
        soc = soc[0] + (soc[1] * (1.0/256.0));
        if (DEBUG) server.log("cell soc%: " + soc);
        return soc;
    }

    /*
    returns cell voltage in volts.
    note that cell voltage is only valid 500ms after startup.
    */
    function voltage() {
        const MV_PER_COUNT = 1.25;
        local voltage = i2c_.read(I2C_ADDR, REG_VCELL, 2);
        if (voltage ==null) {
            server.log("error: could not read SoC monitor voltage");
            return;
        }
        voltage = to_int_(voltage) >> 4; // account for unused LSBs
        voltage = (voltage * MV_PER_COUNT) / 1000.0; // convert to volts
        if (DEBUG) server.log("cell voltage: " + voltage);
        return voltage
    }
    
    /* 
    reads the silicon version of the SoC monitor
    this is mostly useful as a debug tool to make sure the IC is connected and working
    */
    function version(){
        if (DEBUG) server.log("read SoC monitor version: ");
        local version = i2c_.read(I2C_ADDR, "\x08", 2);
        if (version == null) {
            server.log("error: could not read SoC monitor version");
            return
        }
        // convert the bytes returned to a single integer value
        version = to_int_(version);
        if (DEBUG) server.log(version);
        
        return version;
    }
    
    /*
    converts a string of bytes to a single integer
    used for deserialization of I2C returns
    */
    function to_int_(str_val){
        local out_val = 0;
        foreach (i, byte in str_val) {
            out_val += byte<<( 8 * (str_val.len() - i - 1) );
        }
        return out_val
    }
};

class range_sensor {
    
    trig_ = null;
    echo_ = null;

    constructor(trig_pin, echo_pin) {
        trig_ = trig_pin;
        echo_ = echo_pin;
    }

    function range_in() {
        // get the start time
        local start_ms = hardware.millis();
        
        // send trigger pulse
        trig_.write(0);
        trig_.write(1);
        trig_.write(0);
        
        // Wait for the echo pulse to start
        while(echo_.read() == 0){
            if ((hardware.millis() - start_ms) > 500) {
                // TODO handle millis() rollover intelligently
                if (DEBUG) server.log("timeout on pulse start");
                start_ms = hardware.millis();
                break;
            }
        }
        local echobegin_us = hardware.micros();
        // Wait for the echo pulse to end
        while(echo_.read() == 1){
            if ((hardware.millis() - start_ms) > 500){
                // TODO handle invalid ranges intelligently
                if (DEBUG) server.log("timeout on pulse end");
                break;
            }
        }
        local echolen_us = hardware.micros() - echobegin_us;
        
        return (echolen_us / 148.0);
    }
};

function setup() {
    // only connect to the server by default in debug mode, to reduce power draw
    if (DEBUG) server.connect();
    
    trig <- hardware.pin9;
    trig.configure(DIGITAL_OUT, 0);
    echo <- hardware.pinD;
    echo.configure(DIGITAL_IN);

    // SoC monitor I2C bus
    i2c_pullup <- hardware.pinE;
    i2c_pullup.configure(DIGITAL_OUT, 1);
    i2c <- hardware.i2c12;
    i2c.configure(CLOCK_SPEED_400_KHZ);
}

// ------------------------------------------
// MAIN PROGRAM ENTRY POINT
// ------------------------------------------
setup();
local rs = range_sensor(trig, echo);
local d = detector();
local soc = batt_monitor(i2c);
local prev_state = STATE.nobody;
local curr_state = STATE.nobody;
function mainloop() {
    local range_in = rs.range_in();
    
    local cell_soc = soc.charge_percent();

    // detect state transitions
    prev_state = curr_state;
    curr_state = d.detect_person(range_in);
    if(curr_state != prev_state) {
        // connect to server (if we're not already), and wait for 
        // connection to complete
        if (!DEBUG) server.connect();
        while (!server.isconnected());
        server.log(curr_state)
        agent.send("state", curr_state);
        if (!DEBUG) server.disconnect();
    }
    
    if (DEBUG) agent.send("range", range_in);
    if (DEBUG) server.log("range " + range_in + " inches")
    imp.wakeup(1.0, mainloop); 
}
mainloop();
