# Blueprints

## Konventionen

- Jeder Blueprint hat einen eigenen Ordner unter `/blueprints/`
- Jeder Blueprint-Ordner enthaelt:
  - `blueprint_<name>.yaml` - Die Blueprint-Definition
  - `README.md` - Dokumentation mit Features, Installation und Konfiguration
- Blueprints folgen dem Home Assistant Blueprint-Format
- Quellenangaben bei Community-basierten Blueprints erforderlich

## Verifikation nach Aenderungen

Nach jeder Blueprint-Aenderung alle drei Schritte ausfuehren:

### 1. YAML Validation

Home Assistant Blueprints verwenden `!input` Custom Tags. Pythons `yaml.SafeLoader` kennt diese nicht.

**Immer diesen Validator verwenden:**
```bash
python3 -c "
import yaml
class L(yaml.SafeLoader):
    pass
def c(loader, tag_suffix, node):
    if isinstance(node, yaml.ScalarNode): return loader.construct_scalar(node)
    elif isinstance(node, yaml.SequenceNode): return loader.construct_sequence(node)
    elif isinstance(node, yaml.MappingNode): return loader.construct_mapping(node)
L.add_multi_constructor('', c)
with open('DATEI.yaml') as f:
    yaml.load(f, Loader=L)
print('YAML valid')
"
```

**NICHT verwenden** (scheitert an `!input` Tags):
- `yaml.SafeLoader.add_constructor('!input', ...)` — funktioniert nicht zuverlaessig
- `yaml.safe_load()` ohne Custom Loader

### 2. Strukturelle Validierung

Nach dem YAML-Parsing pruefen ob neue/geaenderte Inputs, Variablen und Defaults korrekt sind.
Verwendet den gleichen Custom Loader wie oben, parst dann die Datenstruktur:

```bash
python3 -c "
import yaml
class L(yaml.SafeLoader):
    pass
def c(loader, tag_suffix, node):
    if isinstance(node, yaml.ScalarNode): return loader.construct_scalar(node)
    elif isinstance(node, yaml.SequenceNode): return loader.construct_sequence(node)
    elif isinstance(node, yaml.MappingNode): return loader.construct_mapping(node)
L.add_multi_constructor('', c)
with open('DATEI.yaml') as f:
    data = yaml.load(f, Loader=L)
# Beispiel-Pruefungen:
inputs = data['blueprint']['input']['SECTION']['input']
print('Input vorhanden:', 'KEY' in inputs)
print('Default-Wert:', inputs['KEY']['default'])
variables = data.get('variables', {})
print('Variable vorhanden:', 'KEY' in variables)
"
```

Typische Pruefungen:
- Neue Inputs existieren in der richtigen Section
- Default-Werte stimmen
- Alte/entfernte Inputs/Variablen sind weg
- Variablen-Block enthaelt alle erwarteten Keys

### 3. Grep-Verifikation

Nach Aenderungen mit Grep pruefen ob:
- Fixes an allen erwarteten Stellen angewendet wurden (z.B. `Grep pattern output_mode:content` mit Zeilennummern)
- Keine unbeabsichtigten Stellen veraendert wurden
- Anzahl von Vorkommen stimmt (z.B. Anzahl `notify.notify` Aufrufe, Anzahl Wait-for-Trigger Bloecke)
