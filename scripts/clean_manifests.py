import sys
import yaml

def clean_dict(d):
    if not isinstance(d, dict):
        return d
    
    # Fields to remove
    to_remove = [
        'uid', 'resourceVersion', 'creationTimestamp', 'generation', 
        'selfLink', 'managedFields', 'ownerReferences', 'status',
        'nodeName', 'podIP', 'podIPs', 'hostIP', 'hostIPs', 'startTime',
        'clusterIP', 'clusterIPs'
    ]
    
    new_d = {}
    for k, v in d.items():
        if k in to_remove:
            continue
        if k == 'annotations':
            # Remove kubectl internal annotations
            v = {ak: av for ak, av in v.items() if not ak.startswith('kubectl.kubernetes.io/') and not ak.startswith('deployment.kubernetes.io/')}
            if not v:
                continue
        
        # Remove specific spec fields that are usually system-assigned
        if k == 'spec' and isinstance(v, dict):
            v.pop('nodePort', None) # Remove nodePort if present, let it be reassigned
        
        if isinstance(v, dict):
            new_d[k] = clean_dict(v)
        elif isinstance(v, list):
            new_d[k] = [clean_dict(i) if isinstance(i, dict) else i for i in v]
        else:
            new_d[k] = v
    return new_d

def main():
    if len(sys.argv) < 2:
        print("Usage: python clean_manifests.py <input_yaml>")
        sys.exit(1)
        
    with open(sys.argv[1], 'r') as f:
        data = yaml.safe_load(f)
    
    if data.get('kind') == 'List':
        items = data.get('items', [])
        # Filter out Pods and ReplicaSets as they are managed by Deployments
        filtered_items = [i for i in items if i.get('kind') not in ['Pod', 'ReplicaSet', 'Endpoints']]
        cleaned_items = [clean_dict(i) for i in filtered_items]
        
        for item in cleaned_items:
            print("---")
            print(yaml.dump(item, sort_keys=False))
    else:
        cleaned = clean_dict(data)
        print(yaml.dump(cleaned, sort_keys=False))

if __name__ == "__main__":
    main()
