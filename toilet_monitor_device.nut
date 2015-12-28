DEBUG <- false;

/*
debug printing function to be used only during live debugging
there should be no calls to this left in code, this is a live
debugging tool only
*/
function debugprint(string) {
    if (!server.isconnected()) server.connect();
    while (!server.isconnected());
    server.log("DEBUG: "  + string);
}

/*
range_sensor implements the interface to the HC-SR04 ultrasonic range sensor
*/
class range_sensor {
    range_in = 0.0;
    
    trig_ = null;
    echo_ = null;

    constructor(trig_pin, echo_pin) {
        trig_ = trig_pin;
        echo_ = echo_pin;
    }

    function range() {
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
        
        range_in = (echolen_us / 148.0);
        return range_in;
    }
};

/*
detector is a state machine used to detect the presence of a person in front of the
toilet monitor.
*/
enum STATE {
    nobody = "nobody",
    pee = "pee",
    poop = "poop",
    error = "error"
    init = "init"
}
class detector {
    min_range = 3.0;
    max_range_poo = 30.0;
    max_range_pee = 40.0;
    max_range = 2000.0;
    count_thresh = 4; // number of samples that must fall in a range bin
    state = STATE.init;

    sensor_ = 1234;
    pee_count_ = 0;
    poo_count_ = 0;
    prev_state_ = STATE.init;
    
    /*
    requires a range sensor to be passed in
    */
    constructor(rs){
        sensor_ = rs;
    }

    /*
    checks the current range, sees if a person is present, and then checks if the 
    person present status has changed since last called.
    returns true if the status has changed
    */
    function changed() {
        state = detect_person(sensor_.range());
        if (prev_state_ != state) {
            prev_state_ = state;
            return true;
        }
        return false;
    }

    /*
    updates the state and returns it to the caller
    */
    function detect_person(range_in) {
        if ((range_in < min_range) || (range_in > max_range)) {
            // range is invalid
            if (DEBUG) server.log("error: unexpected range value: " + range_in);
            state = STATE.error;
            pee_count_ = 0;
            poo_count_ = 0;
        }
        else if (range_in < max_range_poo) {
            // range is valid and within poop range
            poo_count_++;
            if (poo_count_ > count_thresh) {
                state = STATE.poop;
                poo_count_ = count_thresh;
                pee_count_ = 0;
            }
        }
        else if (range_in < max_range_pee) {
            // range is valid and in pee range
            pee_count_++;
            if (pee_count_ > count_thresh) {
                state = STATE.pee;
                pee_count_ = count_thresh;
                poo_count_ = 0;
            }
        }
        else {
            poo_count_--;
            pee_count_--;
            if ((poo_count_ < 0) || (pee_count_ < 0)) {
                poo_count_ = 0;
                pee_count_ = 0;
                state = STATE.nobody;
            }
        }
        return state;
    }
};

/*
batt_monitor implements the interface to the MAX17043 SoC monitor.
*/
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
    prev_soc = 0.0;

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
            if (DEBUG) server.log("error: could not read SoC charge percentage");
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
            if (DEBUG) server.log("error: could not read SoC monitor voltage");
            return;
        }
        voltage = to_int_(voltage) >> 4; // account for unused LSBs
        voltage = (voltage * MV_PER_COUNT) / 1000.0; // convert to volts
        if (DEBUG) server.log("cell voltage: " + voltage);
        return voltage
    }

    /*
    returns true if the SoC has changed appreciably since this function last returned true
    this allows the system to only take action on large soc changes
    */
    function changed() {
        const HYSTERESIS_PERCENT = 0.5; // only report a change if SoC has changed by more than this from last update
        local soc = charge_percent();
        if (soc != null) {
            if (math.abs(soc - prev_soc) > HYSTERESIS_PERCENT) {
                prev_soc = soc;
                return true;
            }
        }
        return false; // note that we also get here if the SoC reading is invalid
    }

    /* 
    reads the silicon version of the SoC monitor
    this is mostly useful as a debug tool to make sure the IC is connected and working
    */
    function version(){
        if (DEBUG) server.log("read SoC monitor version: ");
        local version = i2c_.read(I2C_ADDR, "\x08", 2);
        if (version == null) {
            if (DEBUG) server.log("error: could not read SoC monitor version");
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

/*
performs setup of all hardware pins and system states
*/
function setup() {
    server.setsendtimeoutpolicy(SUSPEND_ON_ERROR, WAIT_TIL_SENT, 60.0);
    
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

function send_signature() {
    if (!server.isconnected()) server.connect();
    while (!server.isconnected());
    
    server.log(format(  "********************************\n" +
                        "TOILET MONITOR ONLINE\n" +
                        "MAC: %s \nSSID: %s \nRSSI: %d \n" +
                        "********************************\n",
                        imp.getmacaddress(), imp.getssid(), imp.getrssi() ));
    if (!DEBUG) {
        server.log("disconnecting")
        server.flush(30.0);
        server.disconnect();
    }
}


// ------------------------------------------
// MAIN PROGRAM ENTRY POINT
// ------------------------------------------

// initialize hardware:
setup();

// instantiate objects:
local rs = range_sensor(trig, echo);
local d = detector(rs.weakref());
local soc = batt_monitor(i2c);

// let server know that we're online
send_signature();

function mainloop() {
    local cell_soc = 0.0;
    local cell_volts = 0.0;

    // detect state transitions
    if(d.changed() || soc.changed() || DEBUG) {
        // connect to server (if we're not already)
        if (!server.isconnected()) server.connect();
        while (!server.isconnected());
        
        // update state and range
        server.log("range: " + rs.range_in + "in  state: " + d.state)
        agent.send("state", d.state);
        agent.send("range", rs.range_in);

        // update soc
        cell_soc = soc.charge_percent();
        cell_volts = soc.voltage();
        server.log("batt: " + cell_volts + "V  " + cell_soc + "%");
        agent.send("battery_status", [cell_soc, cell_volts]);
        
        if (!DEBUG) {
            server.log("disconnecting")
            server.flush(30.0);
            server.disconnect();
        }
    }

    // sleep till next loop iteration
    imp.wakeup(0.5, mainloop); 
}
mainloop();

server.onunexpecteddisconnect(function(unused){server.connect()});
