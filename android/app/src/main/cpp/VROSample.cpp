//
//  VROSample.cpp
//  ViroRenderer
//
//  Created by Raj Advani on 11/9/16.
//  Copyright © 2016 Viro Media. All rights reserved.
//
#include "Viro.h"
#include "VROSample.h"
#include "VRORenderer.h"
#include "VRODriverOpenGLAndroid.h"
#include "VROImageAndroid.h"
#include "VROSceneRendererCardboard.h"
#include "VROVideoTextureAndroid.h"
#include "VROVideoTextureAVP.h"

VROSample::VROSample() {

}

VROSample::~VROSample() {

}

std::shared_ptr<VROSceneController> VROSample::loadBoxScene(std::shared_ptr<VROFrameSynchronizer> frameSynchronizer,
                                                            VRODriver &driver) {

    _driver = &driver;
    frameSynchronizer->addFrameListener(shared_from_this());

    _soundEffect = driver.newSoundEffect("btn_tap.mp3");
    _audio = driver.newAudioPlayer("underwater.mp3");

    std::shared_ptr<VROSceneController> sceneController = std::make_shared<VROSceneController>();
    std::shared_ptr<VROScene> scene = sceneController->getScene();
    scene->setBackgroundCube(getNiagaraTexture());

    std::shared_ptr<VRONode> rootNode = std::make_shared<VRONode>();
    rootNode->setPosition({0, 0, 0});

    std::shared_ptr<VROLight> ambient = std::make_shared<VROLight>(VROLightType::Ambient);
    ambient->setColor({ 0.4, 0.4, 0.4 });

    std::shared_ptr<VROLight> spotRed = std::make_shared<VROLight>(VROLightType::Spot);
    spotRed->setColor({ 1.0, 0.0, 0.0 });
    spotRed->setPosition( { -5, 0, 0 });
    spotRed->setDirection( { 1.0, 0, -1.0 });
    spotRed->setAttenuationStartDistance(20);
    spotRed->setAttenuationEndDistance(30);
    spotRed->setSpotInnerAngle(2.5);
    spotRed->setSpotOuterAngle(5.0);

    std::shared_ptr<VROLight> spotBlue = std::make_shared<VROLight>(VROLightType::Spot);
    spotBlue->setColor({ 0.0, 0.0, 1.0 });
    spotBlue->setPosition( { 5, 0, 0 });
    spotBlue->setDirection( { -1.0, 0, -1.0 });
    spotBlue->setAttenuationStartDistance(20);
    spotBlue->setAttenuationEndDistance(30);
    spotBlue->setSpotInnerAngle(2.5);
    spotBlue->setSpotOuterAngle(5.0);

    rootNode->addLight(ambient);
    rootNode->addLight(spotRed);
    rootNode->addLight(spotBlue);

    scene->addNode(rootNode);

    /*
     Create the box node.
     */
    std::shared_ptr<VROBox> box = VROBox::createBox(2, 4, 2);
    box->setName("Box 1");

    _videoA = std::make_shared<VROVideoTextureAVP>();
    _videoA->loadVideoFromAsset("vest.mp4", driver);
    _videoA->setLoop(true);
    _videoA->play();

    _material = box->getMaterials()[0];
    _material->setLightingModel(VROLightingModel::Lambert);
    //_material->getDiffuse().setTexture(_videoA);
    _material->getDiffuse().setTexture(std::make_shared<VROTexture>(std::make_shared<VROImageAndroid>("boba.png")));
    _material->getSpecular().setTexture(std::make_shared<VROTexture>(std::make_shared<VROImageAndroid>("specular.png")));

    std::shared_ptr<VRONode> boxNode = std::make_shared<VRONode>();
    boxNode->setGeometry(box);
    boxNode->setPosition({0, 0, -5});

    rootNode->addChildNode(boxNode);
    //boxNode->addConstraint(std::make_shared<VROBillboardConstraint>(VROBillboardAxis::All));

    VROTransaction::begin();
    VROTransaction::setAnimationDuration(6);

    spotRed->setPosition({5, 0, 0});
    spotRed->setDirection({-1, 0, -1});

    spotBlue->setPosition({-5, 0, 0});
    spotBlue->setDirection({1, 0, -1});

    VROTransaction::commit();

    return sceneController;
}

std::shared_ptr<VROTexture> VROSample::getNiagaraTexture() {
    std::vector<std::shared_ptr<VROImage>> cubeImages = {
            std::make_shared<VROImageAndroid>("px.png"),
            std::make_shared<VROImageAndroid>("nx.png"),
            std::make_shared<VROImageAndroid>("py.png"),
            std::make_shared<VROImageAndroid>("ny.png"),
            std::make_shared<VROImageAndroid>("pz.png"),
            std::make_shared<VROImageAndroid>("nz.png")
    };

    return std::make_shared<VROTexture>(cubeImages);
}

static int count = 0;

void VROSample::reticleTapped(VROVector3f ray, const VRORenderContext *context) {
    if (count == 0) {
        _videoA->setVolume(0.5);
    }
    else if (count == 1) {
        _videoA->setMuted(true);
    }
    else if (count == 2) {
        _videoA->setMuted(false);
    }
    else if (count == 3) {
        _videoA->setVolume(1.0);
    }
    else if (count == 4) {
        _videoA->seekToTime(2);
    }
    else if (count == 5) {
        _videoA->pause();
    }
    else if (count == 6) {
        _videoA->play();
    }

    ++count;
    if (count == 7) {
        count = 0;
    }
}

void VROSample::onFrameWillRender(const VRORenderContext &context) {

}

void VROSample::onFrameDidRender(const VRORenderContext &context) {

}