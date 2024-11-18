#!/usr/bin/python3
# -*- coding: utf-8 -*-
# Author: Ist wurst...
import pdb
import sys
import xml.etree.ElementTree as ET
import json
#from graphviz import Digraph
import time
from xml.etree.ElementTree import Element
from ipaddress import IPv4Interface


def get_zones(rulebase: Element, zone_list: list = None):
    """

    :param zone_list:
    :type rulebase: Element
    """

    if zone_list is None:
        zone_list = []

    rule_types = ["security", "application-override", "decryption", "tunnel-inspect", "authentication", "nat", "qos", "pbf", "sdwan", "network-packet-broker", "dos"]
    for rule_type in rule_types:
        rule_type_xpath = "./" + rule_type + "/rules"
        rules = rulebase.find(rule_type_xpath)
        if rules is not None:
            for rule in rules:
                if rule.find('./disabled') is not None and rule.find('./disabled').text == "no":
                    zone_positions = ["./to/member", "./from/member"]
                    for zone_pos in zone_positions:
                        for zone in rule.findall(zone_pos):
                            if zone.text != "any" and zone.text not in zone_list:
                                zone_list.append(zone.text)

    return zone_list

def get_values_pa(xml_output):

    tree = ET.parse(xml_output)
    root = tree.getroot()
    dict = {}

    dict["template"] = {}
    for tmpl in root.findall("./devices/entry/template/entry"):
        tmpl_name = tmpl.attrib["name"]
        dict["template"][tmpl_name] = {}
        dict["template"][tmpl_name]["vsys"] = {}
        # collect zones
        for vsys in tmpl.findall("./config/devices/entry/vsys/entry"):
            vsys_name = vsys.attrib["name"]
            dict["template"][tmpl_name]["vsys"][vsys_name] = {}
            dict["template"][tmpl_name]["vsys"][vsys_name]["zone"] = {}
            for zone in vsys.findall("./zone/entry"):
                zone_name = zone.attrib["name"]
                if_list = []
                if zone.findall("./network/layer3/member") is not None:
                    for unit_name in zone.findall("./network/layer3/member"):
                        if_list.append(unit_name.text)
                dict["template"][tmpl_name]["vsys"][vsys_name]["zone"][zone_name] = if_list

    dict["template-stack"] = {}
    for tmplstk in root.findall("./devices/entry/template-stack/entry"):
        tmplstk_name = tmplstk.attrib["name"]
        dict["template-stack"][tmplstk_name] = {}

        tmpl_list = []
        for tmpl in tmplstk.findall("./templates/member"):
            tmpl_name = tmpl.text
            tmpl_list.append(tmpl_name)
        dict["template-stack"][tmplstk_name]["templates"] = tmpl_list

        dvc_list = []
        for dvc in tmplstk.findall("./devices/entry"):
            dvc_id = dvc.attrib["name"]
            dvc_list.append(dvc_id)
        dict["template-stack"][tmplstk_name]["devices"] = dvc_list


    dict["device-group"] = {}
    for dg in root.findall("./devices/entry/device-group/entry"):
        dg_name = dg.attrib["name"]
        dict["device-group"][dg_name] = {}

        dvc_list = []
        for dvc in dg.findall("./devices/entry"):
            dvc_id = dvc.attrib["name"]
            vsyses = dvc.findall("./vsys/entry")
            if not vsyses:
                print("element vsys not found or element vsys has no subelement! dg: " + str(dg.attrib["name"]))
                data = dvc_id
                dvc_list.append(data)
            if vsyses is None:
                print("subelement exist, but element (vsysid) not found! dg: " + str(dg.attrib["name"]))
                data = dvc_id
                dvc_list.append(data)
            else:
                for vsys in dvc.findall("./vsys/entry"):
                    vsys_name = vsys.attrib["name"]
                    data = dvc_id + ' - ' + vsys_name
                    dvc_list.append(data)
        dict["device-group"][dg_name]["devices"] = dvc_list
        dict["device-group"][dg_name]["zones"] = []
        rule_positions = ["pre", "post"]
        zone_list_tmp = []
        zone_list = []
        for rule_pos in rule_positions:
            xpath = "./" + rule_pos + "-rulebase"
            dg_rulebase = dg.find(xpath)
            if dg_rulebase is not None:
                zone_list = get_zones(dg_rulebase, zone_list_tmp)
                zone_list_tmp = zone_list
        dict["device-group"][dg_name]["zones"] = zone_list


    for dg in root.findall("./readonly/devices/entry/device-group/entry"):
        dg_name = dg.attrib["name"]
        for parent_dg in dg.findall("./parent-dg"):
            if parent_dg is not None:
                dg_p_name = parent_dg.text
            else:
                dg_p_name = "no parent"
            dict["device-group"][dg_name]["parent"] = dg_p_name

    json_obj = json.dumps(dict, indent=4)
    print(json_obj)
    return dict


def digraph_creator(dict):


    g = Digraph(
        name='config_topo_dg',
        filename='config_topo_dg.gv',
        graph_attr={'fontsize': '30', 'rankdir': 'DT', 'splines': 'true', 'overlap': 'scale', 'imagepath': 'C:/Users/akdaniel/Downloads/nw_topo/', 'label': 'Palo Alto Panorama Configuration Topology - device-groups'},
        strict=True
    )

    g.attr('node', shape='box')

    for dg in dict['device-group']:

        table = '<table border="1" cellborder="0" cellpadding="2" bgcolor="#33CBFF">\n'
        table += ' <tr>\n  <td color="#089FD3" bgcolor="#089FD3" align="center" border="5">\n   <font color="white">device-group: {tmpl_name}</font>\n  </td>\n </tr>\n'.format(tmpl_name=dg)

        groupname = 'devices'
        if groupname in dict['device-group'][dg]:
            table += ' <tr>\n  <td align="left" port="{group_id}">&#8226; assigned {group_name}</td>\n </tr>\n'.format(group_id=groupname, group_name=groupname)
            for id, value in enumerate(dict['device-group'][dg]['devices']):
                entry_id = groupname + str(id)
                table += ' <tr>\n  <td align="left" port="{entry_id}">  &#183; {entry_name}</td>\n </tr>\n'.format(entry_id=entry_id, entry_name=value)

        table += '</table>'
        label = '<\n' + table + '\n>'
        g.node(dg, penwidth='0', fontname='Arial', label=label)

        if "parent" in dict['device-group'][dg]:
            dgparent = dict['device-group'][dg]['parent']
            g.edge(dg, dgparent, dir='back', color='#089FD3')

    #g.view()

    g = Digraph(
        name='config_topo_tmpl',
        filename='config_topo_tmpl.gv',
        graph_attr={'fontsize': '30', 'rankdir': 'DT', 'splines': 'true', 'overlap': 'scale', 'imagepath': 'C:/Users/akdaniel/Downloads/nw_topo/', 'label': 'Palo Alto Panorama Configuration Topology - template-stacks'},
        strict=True
    )

    g.attr('node', shape='box')

    for template in dict['template']:

        table = '<table border="1" cellborder="0" cellpadding="2" bgcolor="#FFD580">\n'
        table += ' <tr>\n  <td color="orange" bgcolor="orange" align="center" border="5">\n   <font color="white">Template: {tmpl_name}</font>\n  </td>\n </tr>\n'.format(tmpl_name=template)
        table += ' <tr>\n  <td align="left" port="{group_id}"> &#8226; {group_name} configuration</td>\n </tr>\n'.format(group_id='vsys', group_name='vsys')
        i = 0
        for vsys in dict['template'][template]['vsys']:
            entry_id = 'vsys_' + str(i)
            i += 1
            table += ' <tr>\n  <td align="left" port="{entry_id}"> &#8226; {entry_name}</td>\n </tr>\n'.format(entry_id=entry_id, entry_name=vsys)
            table += ' <tr>\n  <td align="left" port="{group_id}">  &#8226; {group_name} configuration</td>\n </tr>\n'.format(group_id='zone', group_name='zone')
            j = 0
            for zone in dict['template'][template]['vsys'][vsys]['zone']:
                subentry_id = 'zone' + str(j)
                j += 1
                table += ' <tr>\n  <td align="left" port="{entry_id}">   &#183; {entry_name}</td>\n </tr>\n'.format(entry_id=subentry_id, entry_name=zone)

        table += '</table>'
        label = '<\n' + table + '\n>'
        g.node(template, penwidth='0', fontname='Arial', label=label)

    for templatestack in dict['template-stack']:

        table = '<table border="1" cellborder="0" cellpadding="2" bgcolor="#33CBFF">\n'
        table += ' <tr>\n  <td color="#089FD3" bgcolor="#089FD3" align="center" border="5">\n   <font color="white">Template-stack: {tmplst_name}</font>\n  </td>\n </tr>\n'.format(tmplst_name=templatestack)

        groupname = 'devices'
        if groupname in dict['template-stack'][templatestack]:
            table += ' <tr>\n  <td align="left" port="{group_id}">&#8226; assigned {group_name}</td>\n </tr>\n'.format(group_id=groupname, group_name=groupname)
            for id, value in enumerate(dict['template-stack'][templatestack][groupname]):
                entry_id = groupname + str(id)
                table += ' <tr>\n  <td align="left" port="{entry_id}">  &#183; {entry_name}</td>\n </tr>\n'.format(entry_id=entry_id, entry_name=value)

        groupname = 'templates'
        if groupname in dict['template-stack'][templatestack]:
            table += ' <tr>\n  <td align="left" port="{group_id}">&#8226; assigned {group_name}</td>\n </tr>\n'.format(group_id=groupname, group_name=groupname)
            for id, value in enumerate(dict['template-stack'][templatestack][groupname]):
                entry_id = groupname + str(id)
                table += ' <tr>\n  <td align="left" port="{entry_id}">  &#183; {entry_name}</td>\n </tr>\n'.format(entry_id=entry_id, entry_name=value)

        table += '</table>'
        label = '<\n' + table + '\n>'
        g.node(templatestack, penwidth='0', fontname='Arial', label=label)

        templatelist = dict['template-stack'][templatestack]['templates']
        g.edge(templatestack, templatelist[0], dir='back', color='#089FD3')
        for i in (range(len(templatelist)-1)):
            g.edge(templatelist[i], templatelist[i+1], dir='back', color='orange')

    #g.view()
    #print(g.source)


def main(argv):

    file_path = 'C:/Users/dakos/Downloads/Panorama_20241112/'
    xml_input = file_path + 'panorama.xml'

    time_str = time.strftime("%Y%m%d_%H%M%S")
    result_output_json = file_path + 'panorama_config_topology_' + time_str + '.json'

    config_data = get_values_pa(xml_input)
    with open(result_output_json, 'w') as panorama_config:
        panorama_config.write(json.dumps(config_data))

    #with open('C:\\Users\\akdaniel\\Downloads\\running-config\\panorama_config_topology.json', 'r') as panorama_config:
    #    config_data = json.load(panorama_config)

    #digraph_creator(config_data)

if __name__ == "__main__":
    main(sys.argv[1:])
