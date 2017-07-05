//
//  VROPhysicsShape.m
//  ViroRenderer
//
//  Copyright © 2017 Viro Media. All rights reserved.
//

#include "VROPhysicsShape.h"
#include "VROBox.h"
#include "VROSphere.h"
#include "VROLog.h"
#include "VRONode.h"
#include <btBulletDynamicsCommon.h>
const std::string VROPhysicsShape::kSphereTag = "sphere";
const std::string VROPhysicsShape::kBoxTag = "box";
const std::string VROPhysicsShape::kAutoCompoundTag = "AutoCompound";

VROPhysicsShape::VROPhysicsShape(VROShapeType type, std::vector<float> params) {
    if (type != VROShapeType::Sphere || VROShapeType::Box){
        perror("Attempted to construct unsupported VROPhysicsShape type!");
    }

    if ((type == VROShapeType::Sphere && params.size() < 1)
        || (type == VROShapeType::Box && params.size() < 3)){
        perror("Attempted to construct VROPhysics shape with incorrect parameters!");
    }

    _type = type;
    _bulletShape = generateBasicBulletShape(type, params);
}

VROPhysicsShape::VROPhysicsShape(std::shared_ptr<VRONode> node, bool hasCompoundShapes){
    if (hasCompoundShapes) {
        btCompoundShape* compoundShape = new btCompoundShape();
        generateCompoundBulletShape(*compoundShape, node, node);
        _bulletShape = compoundShape;
        _type = VROShapeType::AutoCompound;
    } else {
        _bulletShape = generateBasicBulletShape(node);
        _type = VROShapeType::Auto;
    }
}

VROPhysicsShape::~VROPhysicsShape() {
    if (_bulletShape != nullptr){
        delete(_bulletShape);
    }
}

btCollisionShape* VROPhysicsShape::getBulletShape() {
    return _bulletShape;
}

bool VROPhysicsShape::getIsGeneratedFromGeometry() {
    return _type == Auto || _type == AutoCompound;
}

bool VROPhysicsShape::getIsCompoundShape() {
    return _type == AutoCompound;
}

btCollisionShape* VROPhysicsShape::generateBasicBulletShape(std::shared_ptr<VRONode> node) {
    if (node->getGeometry() == nullptr) {
        pwarn("Warn: Attempted to create a physics shape from a node without defined geometry!");
        return nullptr;
    }

    std::shared_ptr<VROGeometry> geometry = node->getGeometry();
    std::vector<float> params;
    VROPhysicsShape::VROShapeType type;
    if (dynamic_cast<VROSphere*>(geometry.get()) != nullptr) {
        type = VROPhysicsShape::VROShapeType::Sphere;

        // Grab the max span to account for skewed spheres - we simply
        // assume a perfect sphere for these situations.
        VROBoundingBox bb = node->getBoundingBox();
        float maxSpan = std::max(std::max(bb.getSpanX(), bb.getSpanY()), bb.getSpanZ());
        params.push_back(maxSpan/2);
    } else {
        type = VROPhysicsShape::VROShapeType::Box;
        VROBoundingBox bb = node->getBoundingBox();
        params.push_back(bb.getSpanX() / 2);
        params.push_back(bb.getSpanY() / 2);
        params.push_back(bb.getSpanZ() / 2);
    }
    return generateBasicBulletShape(type, params);
}


btCollisionShape* VROPhysicsShape::generateBasicBulletShape(VROPhysicsShape::VROShapeType type, std::vector<float> params) {
    if (type == VROPhysicsShape::VROShapeType::Box) {
        return new btBoxShape(btVector3(params[0],params[1],params[2]));
    } else if (type == VROPhysicsShape::VROShapeType::Sphere) {
        return new btSphereShape(btScalar(params[0]));
    } else if (type != VROPhysicsShape::VROShapeType::Auto &&
               type != VROPhysicsShape::VROShapeType::AutoCompound) {
        perror("Attempted to grab a bullet shape from a mis-configured VROPhysicsShape!");
    }
    return nullptr;
}

void VROPhysicsShape::generateCompoundBulletShape(btCompoundShape &compoundShape,
                                                  const std::shared_ptr<VRONode> &rootNode,
                                                  const std::shared_ptr<VRONode> &currentNode) {
    btCollisionShape* shape = generateBasicBulletShape(currentNode);
    // For each sub shape, bullet requires both rotational / translational offsets.
    if (shape != nullptr) {
        VROVector3f worldPosRoot = rootNode->getComputedPosition();
        VROVector3f worldPosCurrent =  currentNode->getBoundingBox().getCenter();
        VROVector3f offset = worldPosCurrent - worldPosRoot;

        VROQuaternion worldRotCurrent = currentNode->getComputedRotation();
        VROQuaternion worldRotRoot = rootNode->getComputedRotation();
        VROQuaternion offsetRot = worldRotCurrent * worldRotRoot.makeInverse();

        btTransform transform;
        transform.setIdentity();
        transform.setOrigin({offset.x, offset.y, offset.z});
        transform.setRotation({offsetRot.X, offsetRot.Y, offsetRot.Z, offsetRot.W});

        compoundShape.addChildShape(transform, shape);
    }

    // Recurse for all child nodes.
    const std::vector<std::shared_ptr<VRONode>> subNodes = currentNode->getSubnodes();
    for(std::shared_ptr<VRONode> node: subNodes) {
        generateCompoundBulletShape(compoundShape, rootNode, node);
    }
}