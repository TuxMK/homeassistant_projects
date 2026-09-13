/**
 * External converter for the Develco SMSZB-120 smoke detector
 *
 * This converter disables the automatic configure function to prevent
 * crashes on Zigbee coordinators with a limited binding table.
 *
 * Tested with: SLZB-06M (EFR32MG21 chip)
 *
 * Installation:
 * 1. Copy this file into the Zigbee2MQTT configuration folder
 * 2. Register it in configuration.yaml (see README.md)
 * 3. Restart Zigbee2MQTT
 */

const fz = require('zigbee-herdsman-converters/converters/fromZigbee');
const tz = require('zigbee-herdsman-converters/converters/toZigbee');
const exposes = require('zigbee-herdsman-converters/lib/exposes');
const e = exposes.presets;

const definition = {
    zigbeeModel: ['SMSZB-120'],
    model: 'SMSZB-120',
    vendor: 'Develco',
    description: 'Smoke detector with siren (no configure)',
    fromZigbee: [
        fz.ias_smoke_alarm_1,
        fz.temperature,
        fz.battery,
        fz.ias_enroll,
        fz.ias_wd,
    ],
    toZigbee: [
        tz.warning,
        tz.warning_simple,
        tz.ias_max_duration,
        tz.squawk,
    ],
    exposes: [
        e.smoke(),
        e.battery_low(),
        e.tamper(),
        e.test(),
        e.battery(),
        e.battery_voltage(),
        e.temperature(),
        e.warning(),
    ],
    // IMPORTANT: no configure function = no bindings = no crash
};

module.exports = definition;
