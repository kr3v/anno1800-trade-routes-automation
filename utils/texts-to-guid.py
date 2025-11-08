import xml.etree.ElementTree as ET
import json
import sys

guid_to_text = {}

dst_file = sys.argv[1]
for src_file in sys.argv[2:]:
    # Parse the XML file
    tree = ET.parse(src_file)
    root = tree.getroot()

    # Create dictionary mapping GUID to Text
    for text_element in root.findall('.//Texts/Text'):
        guid_elem = text_element.find('GUID')
        text_elem = text_element.find('Text')

        if guid_elem is not None and text_elem is not None:
            guid_to_text[guid_elem.text] = text_elem.text

# Write to JSON file
with open(dst_file, 'w', encoding='utf-8') as f:
    json.dump(guid_to_text, f, indent=2, ensure_ascii=False)

print(f"Converted {len(guid_to_text)} entries from {src_file} to {dst_file}")