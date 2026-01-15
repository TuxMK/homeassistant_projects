/**
 * External Converter fuer Develco SMSZB-120 Rauchmelder
 *
 * Dieser Converter deaktiviert die automatische Configure-Funktion,
 * um Abstuerze bei Zigbee Coordinatoren mit begrenzter Binding Table zu verhindern.
 *
 * Getestet mit: SLZB-06M (EFR32MG21 Chip)
 *
 * Installation:
 * 1. Diese Datei in den Zigbee2MQTT Konfigurationsordner kopieren
 * 2. In configuration.yaml eintragen (siehe README.md)
 * 3. Zigbee2MQTT neustarten
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
    // WICHTIG: Keine configure-Funktion = keine Bindings = kein Crash
};

module.exports = definition;
