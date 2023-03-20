import os
import xml.etree.ElementTree as ET
import pandas as pd

# Pulled from data_extractor.py (which was originally data.py as found on the internet)

def nodelocations_caiso():
    ### Test if nodemap xml exists and download if it does not
    nodemapxml = 'GetPriceContourMap.xml'
    if not os.path.exists(nodemapxml):
        print("Need to download the input file by hand from "
            "'http://wwwmobile.caiso.com/Web.Service.Chart/api/v1/ChartService/GetPriceContourMap'"
            " and save it at (revmpath + 'CAISO/in/GetPriceContourMap.xml).")
        raise Exception("Input file not found")
        # ### For some reason this downloades the file in json format. Just do it by hand.
        # url = 'http://wwwmobile.caiso.com/Web.Service.Chart/api/v1/ChartService/GetPriceContourMap'
        # xmlfile = revmpath+'CAISO/in/GetPriceContourMap.xml'
        # urllib.request.urlretrieve(url, xmlfile)

    ### Import xml nodemap
    tree = ET.parse(nodemapxml)
    root = tree.getroot()

    ### Get  node names, areas, types, and latlons
    names, areas, types, latlonsraw = [], [], [], []
    for node in root.iter(tag='{urn:schemas.caiso.com/mobileapp/2014/03}n'):
        names.append(node.text)

    for node in root.iter(tag='{urn:schemas.caiso.com/mobileapp/2014/03}a'):
        areas.append(node.text)

    for node in root.iter(tag='{urn:schemas.caiso.com/mobileapp/2014/03}p'):
        types.append(node.text)

    latlonsraw = []
    for node in root.iter(tag='{http://schemas.microsoft.com/2003/10/Serialization/Arrays}decimal'):
        latlonsraw.append(float(node.text))

    lats = latlonsraw[::2]
    lons = latlonsraw[1::2]

    ### Generate output dataframe
    dfout = pd.DataFrame({'node': names, 'latitude': lats, 'longitude': lons,
                          'area': areas, 'type': types}).sort_values('node')

    ### Clean up output: Drop nodes with erroneous coordinates
    dfclean = dfout.loc[
        (dfout.longitude > -180)
        & (dfout.longitude < 0)
        & (dfout.latitude > 20)
    ].copy()[['node', 'latitude', 'longitude', 'area', 'type']]

    ### Write output
    dfclean.to_csv('caiso-node-latlon.csv', index=False)
    return dfclean

nodelocations_caiso()
